#include <assert.h>
#include "erl_nif.h"
#include "projects.h"
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

typedef struct { projPJ pj; } pj_cd;

static void cleanup_proj_struct(ErlNifEnv *env, void *cd)
{
  pj_free(((pj_cd *) cd)->pj);
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
  pj_deallocate_grids();
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

  if (!(cd->pj = pj_init_plus(proj_buf))) {
    return error(pj_strerrno(pj_errno));
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

    if (!(cd->pj = pj_init_plus(proj_buf.get()))) {
      return error(pj_strerrno(pj_errno));
    }

    ERL_NIF_TERM resource = enif_make_resource(env, cd.get());
    return ok(resource);
}

static ERL_NIF_TERM expand(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
  pj_cd *p;
  if (!enif_get_resource(env, argv[0], pj_cd_type, (void **) &p)) {
    return error("Failed to get the resource - did you initialize it with create/1?");
  }

  simple_ptr<char> expanded(pj_get_def(p->pj, 0), pj_dalloc);
  int expanded_len = strlen(expanded.get());

  ERL_NIF_TERM res;
  memcpy(enif_make_new_binary(env, expanded_len, &res), expanded.get(), expanded_len);
  return res;
}

static ERL_NIF_TERM transform_2d(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
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
      !enif_get_double(env, point[1], &y)) {
    return error("Invalid point");
  }

  z = 0.0;

  if(pj_is_latlong(from_proj->pj)) {
    x *= DEG_TO_RAD;
    y *= DEG_TO_RAD;
  }
  if(pj_transform( from_proj->pj, to_proj->pj, 1, 1, &x, &y, &z) != 0) {
    return error("transform_2d/3 failed");
  }
  if(pj_is_latlong(to_proj->pj)) {
    x *= RAD_TO_DEG;
    y *= RAD_TO_DEG;
  }

  return ok(enif_make_tuple(env, 2, enif_make_double(env, x), enif_make_double(env, y)));
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

  if(pj_is_latlong(from_proj->pj)) {
    x *= DEG_TO_RAD;
    y *= DEG_TO_RAD;
    z *= DEG_TO_RAD;
  }
  if(pj_transform( from_proj->pj, to_proj->pj, 1, 1, &x, &y, &z) != 0) {
    return error("transform_3d/3 failed");
  }
  if(pj_is_latlong(to_proj->pj)) {
    x *= RAD_TO_DEG;
    y *= RAD_TO_DEG;
    z *= RAD_TO_DEG;
  }

  return ok(enif_make_tuple(env, 3, enif_make_double(env, x), enif_make_double(env, y), enif_make_double(env, z)));
}


static ErlNifFunc reproject_funcs[] =
  {
    {"transform_2d", 3, transform_2d},
    {"transform_3d", 3, transform_3d},
    {"do_create", 1, create},
    {"do_create_from_wkt", 3, create_from_wkt},
    {"expand", 1, expand}
  };

extern "C" {
  ERL_NIF_INIT(Elixir.Reproject, reproject_funcs, load, NULL, NULL, on_unload)
}
