#include <assert.h>
#include "erl_nif.h"
#include "projects.h"
#include <string.h>

#define MAX_PROJ_TERM_SIZE 1024
#define ok(x) enif_make_tuple2(env, reproject_atoms.ok, x)
#define error(x) enif_make_tuple2(env, reproject_atoms.error, enif_make_string(env, x, ERL_NIF_LATIN1))

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
  ERL_NIF_TERM result;
  pj_cd* cd;
  char proj_buf[MAX_PROJ_TERM_SIZE];
  int proj_str_len;

  if (argc != 1) {
    return error("argc is wrong");
  }

  proj_str_len = enif_get_string(env, argv[0], proj_buf, sizeof(proj_buf), ERL_NIF_LATIN1);
  if (proj_str_len <= 0) {
    return error("Failed to initialize the projection");
  }

  cd = enif_alloc_resource(pj_cd_type, sizeof(pj_cd));

  if (!(cd->pj = pj_init_plus(proj_buf))) {
    enif_release_resource(cd);
    return error(pj_strerrno(pj_errno));
  }

  result = enif_make_resource(env, cd);
  enif_release_resource(cd);
  return ok(result);
}

static ERL_NIF_TERM expand(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
  ERL_NIF_TERM res;
  pj_cd *p;
  char* expanded;

  if (!enif_get_resource(env, argv[0], pj_cd_type, (void **) &p)) {
    return error("Failed to get the resource - did you initialize it with create/1?");
  }
  expanded = pj_get_def(p->pj, 0);
  int expanded_len = strlen(expanded);
  memcpy(enif_make_new_binary(env, expanded_len, &res), expanded, expanded_len);
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
    {"expand", 1, expand}
  };

ERL_NIF_INIT(Elixir.Reproject, reproject_funcs, load, NULL, NULL, on_unload)
