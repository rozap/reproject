#include <assert.h>
#include "erl_nif.h"
#include <proj.h>
#include <ogr_srs_api.h>
#include <string.h>
#include <cpl_conv.h>
#include <memory>
#include <vector>

#define MAX_PROJ_TERM_SIZE 1024
#define ok(x) enif_make_tuple2(env, reproject_atoms.ok, x)
#define error(x) enif_make_tuple2(env, reproject_atoms.error, enif_make_string(env, x, ERL_NIF_LATIN1))

namespace {
  template<typename T>
  class simple_ptr {
  public:
    simple_ptr(T* ptr_, void (*destructor_)(void*))
      : ptr(ptr_), destructor(destructor_)
    {}

    ~simple_ptr() {
      if(ptr) destructor(ptr);
    }

    T* get() const {
      return ptr;
    }

    T* extract() {
      T* result = ptr;
      ptr = NULL;
      return result;
    }

    T* operator->() const {
      return ptr;
    }

    operator bool() const {
      return ptr;
    }
  private:
    simple_ptr(simple_ptr<T> const&); // prevent copies

    T* ptr;
    void (*destructor)(void*);
  };
}

static ErlNifResourceType *pj_cd_type = NULL;

static struct {
    ERL_NIF_TERM ok;
    ERL_NIF_TERM error;
} reproject_atoms;

// nb this must be a POD type as it will be simply malloc'd and free'd.
typedef struct {
  PJ_CONTEXT *ctx;
  PJ *pj;
  void* hsr;
} pj_cd;

static void cleanup_proj_struct(ErlNifEnv *env, void *cd)
{
  pj_cd* pcd = (pj_cd*)cd;
  proj_destroy(pcd->pj);
  if (pcd->ctx) proj_context_destroy(pcd->ctx);
  if(pcd->hsr) CPLFree(pcd->hsr);
}

static int load(ErlNifEnv* env, void** _priv, ERL_NIF_TERM _info)
{
  ErlNifResourceType *resource_type = enif_open_resource_type(
    env,
    "reproject",
    "pj_type",
    cleanup_proj_struct,
    ERL_NIF_RT_CREATE,
    NULL
  );

  if (resource_type == NULL) {
    return -1;
  }
  pj_cd_type = resource_type;

  reproject_atoms.ok = enif_make_atom(env, "ok");
  reproject_atoms.error = enif_make_atom(env, "error");

  return 0;
}

static void on_unload(ErlNifEnv* env, void* _priv) {
  return;
}

static ERL_NIF_TERM create(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
  if (argc != 1) {
    return error("argc is wrong");
  }

  char proj_buf[MAX_PROJ_TERM_SIZE];
  int proj_str_len = enif_get_string(env, argv[0], proj_buf, sizeof(proj_buf), ERL_NIF_LATIN1);
  if (proj_str_len <= 0) {
    return error("Failed to initialize the projection");
  }

  simple_ptr<pj_cd> cd((pj_cd*)enif_alloc_resource(pj_cd_type, sizeof(pj_cd)), enif_release_resource);
  // enif_alloc_resource returns uninitialized memory; set every field before any
  // path that could release the resource (the destructor reads all of them).
  cd->ctx = NULL;
  cd->pj = NULL;
  cd->hsr = NULL;
  // Each resource owns a private PROJ context. PROJ contexts are NOT thread-safe,
  // and these NIFs run on multiple BEAM scheduler threads, so sharing
  // PJ_DEFAULT_CTX races and corrupts its proj.db (SQLite) handle.
  cd->ctx = proj_context_create();
  if (!cd->ctx) {
    return error("Failed to create PROJ context");
  }
  cd->pj = proj_create(cd->ctx, proj_buf);
  if (!cd->pj) {
    return error(proj_errno_string(proj_context_errno(cd->ctx)));
  }

  ERL_NIF_TERM result = enif_make_resource(env, cd.get());
  return ok(result);
}

static ERL_NIF_TERM create_from_wkt(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[])
{
    if (argc != 3) {
      return error("argc is wrong");
    }

    int wkt_len;
    if (!enif_get_int(env, argv[0], &wkt_len)) {
      return error("Failed to get len of wkt");
    }

    if (wkt_len >= MAX_PROJ_TERM_SIZE) {
      return error("Projection WKT length exceeds maximum WKT length");
    }

    std::vector<char> wkt_buf(wkt_len + 1);
    int wkt_str_len = enif_get_string(env, argv[1], &wkt_buf[0], wkt_buf.size(), ERL_NIF_LATIN1);
    if (wkt_str_len <= 0) {
      return error("Failed to initialize the wkt from erlang side");
    }

    simple_ptr<void> hSR(OSRNewSpatialReference(&wkt_buf[0]), CPLFree);
    if (!hSR) {
      return error("Failed to initialize OGRSpatialReferenceH");
    }

    int morph_from_esri;
    if (!enif_get_int(env, argv[2], &morph_from_esri)) {
      return error("Is this ESRI or not?");
    }
    if (morph_from_esri > 0) {
      if (OSRMorphFromESRI(hSR.get()) != OGRERR_NONE) {
        return error("Failed to morph from esri");
      }
    }

    char *proj_buf_raw;
    if (OSRExportToProj4(hSR.get(), &proj_buf_raw) != OGRERR_NONE) {
      return error("Failed to export wkt to proj4");
    }
    simple_ptr<char> proj_buf(proj_buf_raw, CPLFree);

    simple_ptr<pj_cd> cd((pj_cd*) enif_alloc_resource(pj_cd_type, sizeof(pj_cd)), enif_release_resource);
    cd->ctx = NULL;
    cd->pj = NULL;
    cd->hsr = NULL;
    cd->ctx = proj_context_create();
    if (!cd->ctx) {
      return error("Failed to create PROJ context");
    }
    cd->pj = proj_create(cd->ctx, proj_buf.get());
    if (!cd->pj) {
      return error(proj_errno_string(proj_context_errno(cd->ctx)));
    }
    cd->hsr = hSR.extract();

    ERL_NIF_TERM resource = enif_make_resource(env, cd.get());
    return ok(resource);
}

static ERL_NIF_TERM expand(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
  pj_cd *p;
  if (!enif_get_resource(env, argv[0], pj_cd_type, (void **) &p)) {
    return error("Failed to get the resource - did you initialize it with create/1?");
  }

  const char* expanded = proj_as_proj_string(p->ctx, p->pj, PJ_PROJ_5, NULL);
  if (!expanded) {
    return error("Failed to get projection definition");
  }
  int expanded_len = strlen(expanded);

  ERL_NIF_TERM res;
  memcpy(enif_make_new_binary(env, expanded_len, &res), expanded, expanded_len);
  return res;
}

static ERL_NIF_TERM get_projection_name(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
  pj_cd *p;
  if (!enif_get_resource(env, argv[0], pj_cd_type, (void **) &p)) {
    return error("Failed to get the resource - did you initialize it with create/1?");
  }

  void* hSR = p->hsr;
  if(!hSR) {
    return error("projection was not created from wkt");
  }

  char const* name = OSRGetAttrValue(hSR, "PROJCS", 0);
  if (name == nullptr) {
    name = OSRGetAttrValue(hSR, "GEOGCS", 0);
  }

  if (name == nullptr) {
    return error("could not determine projection name");
  }

  int name_len = strlen(name);

  ERL_NIF_TERM res;
  memcpy(enif_make_new_binary(env, name_len, &res), name, name_len);
  return ok(res);
}

// Create a normalized CRS-to-CRS transformation between two projections.
// Uses proj_normalize_for_visualization to ensure lon/lat axis order,
// matching the legacy pj_transform behavior.
// The modern API handles degree/radian conversion automatically.
static PJ* create_transform(PJ_CONTEXT *ctx, PJ *from, PJ *to) {
  PJ *P = proj_create_crs_to_crs_from_pj(ctx, from, to, NULL, NULL);
  if (!P) return NULL;

  PJ *P_norm = proj_normalize_for_visualization(ctx, P);
  proj_destroy(P);
  return P_norm;
}

static ERL_NIF_TERM transform_2d(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
  const ERL_NIF_TERM *point;
  int point_count;
  double x, y;
  pj_cd *from_proj, *to_proj;

  if (!enif_get_resource(env, argv[0], pj_cd_type, (void **) &from_proj) ||
      !enif_get_resource(env, argv[1], pj_cd_type, (void **) &to_proj)) {
    return error("Invalid projection terms");
  }

  if(!enif_get_tuple(env, argv[2], &point_count, &point) ||
      !enif_get_double(env, point[0], &x) ||
      !enif_get_double(env, point[1], &y)) {
    return error("Invalid point");
  }

  PJ_CONTEXT *tctx = proj_context_create();
  if (!tctx) {
    return error("Failed to create PROJ context");
  }
  PJ *P = create_transform(tctx, from_proj->pj, to_proj->pj);
  if (!P) {
    proj_context_destroy(tctx);
    return error("Failed to create transformation");
  }

  PJ_COORD input = proj_coord(x, y, 0, 0);
  PJ_COORD output = proj_trans(P, PJ_FWD, input);
  int err = proj_errno(P);
  proj_destroy(P);
  proj_context_destroy(tctx);

  if (err != 0) {
    return error("transform_2d/3 failed");
  }

  return ok(enif_make_tuple(env, 2, enif_make_double(env, output.xy.x), enif_make_double(env, output.xy.y)));
}


static ERL_NIF_TERM transform_3d(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
  const ERL_NIF_TERM *point;
  int point_count;
  double x, y, z;
  pj_cd *from_proj, *to_proj;

  if (!enif_get_resource(env, argv[0], pj_cd_type, (void **) &from_proj) ||
      !enif_get_resource(env, argv[1], pj_cd_type, (void **) &to_proj)) {
    return error("Invalid projection terms");
  }

  if(!enif_get_tuple(env, argv[2], &point_count, &point) ||
      !enif_get_double(env, point[0], &x) ||
      !enif_get_double(env, point[1], &y) ||
      !enif_get_double(env, point[2], &z)) {
    return error("Invalid point");
  }

  PJ_CONTEXT *tctx = proj_context_create();
  if (!tctx) {
    return error("Failed to create PROJ context");
  }
  PJ *P = create_transform(tctx, from_proj->pj, to_proj->pj);
  if (!P) {
    proj_context_destroy(tctx);
    return error("Failed to create transformation");
  }

  PJ_COORD input = proj_coord(x, y, z, 0);
  PJ_COORD output = proj_trans(P, PJ_FWD, input);
  int err = proj_errno(P);
  proj_destroy(P);
  proj_context_destroy(tctx);

  if (err != 0) {
    return error("transform_3d/3 failed");
  }

  return ok(enif_make_tuple(env, 3, enif_make_double(env, output.xyz.x), enif_make_double(env, output.xyz.y), enif_make_double(env, output.xyz.z)));
}


static ErlNifFunc reproject_funcs[] =
  {
    {"transform_2d", 3, transform_2d, ERL_NIF_DIRTY_JOB_CPU_BOUND},
    {"transform_3d", 3, transform_3d, ERL_NIF_DIRTY_JOB_CPU_BOUND},
    {"do_create", 1, create, ERL_NIF_DIRTY_JOB_CPU_BOUND},
    {"do_create_from_wkt", 3, create_from_wkt, ERL_NIF_DIRTY_JOB_CPU_BOUND},
    {"get_projection_name", 1, get_projection_name, 0},
    {"expand", 1, expand, 0}
  };

extern "C" {
  ERL_NIF_INIT(Elixir.Reproject, reproject_funcs, load, NULL, NULL, on_unload)
}
