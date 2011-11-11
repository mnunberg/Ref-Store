#ifndef HREG_H_
#define HREG_H_

#include <perl.h>
#include <stdint.h>

#define HR_DEBUG

#ifndef HR_DEBUG
#define HR_DEBUG(fmt, ...) if(getenv("HR_DEBUG")) { warn(fmt, ## __VA_ARGS__); }
#endif

#define _hashref_eq(r1, r2) \
    (SvROK(r1) && SvROK(r2) && \
    SvRV(r1) == SvRV(r2))

#define _xv_deref_complex_ok(ref, target, to) (SvROK(ref) && SvTYPE(target=(to*)SvRV(ref)) == SVt_PV ## to)

#define _sv_deref_mg_ok(ref, target) (SvROK(ref) && SvTYPE(target=SvRV(ref)) == SVt_PVMG)

#define _mg_action_list(mg) (HR_Action*)mg->mg_ptr

#define HREG_API_INTERNAL

typedef enum {
    HR_ACTION_TYPE_DEL_AV = 1,
    HR_ACTION_TYPE_DEL_HV = 2,
    HR_ACTION_TYPE_CALL_CV = 3
} HR_ActionType_t;

typedef enum {
    HR_KEY_TYPE_NULL= 0,
    HR_KEY_TYPE_PTR = 1,
    HR_KEY_TYPE_STR = 2,
    HR_KEY_TYPE_PV  = 3
} HR_KeyType_t;

typedef enum {
    HR_ACTION_NOT_FOUND,
    HR_ACTION_DELETED,
    HR_ACTION_EMPTY
} HR_DeletionStatus_t;

typedef struct HR_Action HR_Action;

#define HR_ACTION_FIELDS \
    HR_Action *next; \
    char       *key; \
    SV        *collection; \
    unsigned int is_head:1; \
    int        ktype:3; \
    int        atype:4; \

struct HR_Action_HEAD {
    HR_ACTION_FIELDS;
};

struct
// __attribute__((__packed__)) 
HR_Action {
    HR_Action   *next;
    char        *key;
    int          ktype;
    SV          *hashref;
    
    /*TODO:
     instead of just using a hashref, specify an action type, perhaps deleting
     something from an arrayref or calling a subroutine directly
    */
};


HREG_API_INTERNAL
void HR_add_action(
    HR_Action *action_list, char *key, HR_KeyType_t,
    SV *hashref, int want_unique
);

HREG_API_INTERNAL
void HR_trigger_and_free_actions(HR_Action *action_list);


HREG_API_INTERNAL
HR_DeletionStatus_t
HR_del_action(HR_Action *action_list, SV *hashref);

HREG_API_INTERNAL
HR_Action*
HR_free_action(HR_Action *action);

////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////
/// Perl Functions                                                           ///
////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////
void HR_PL_add_actions(SV* objref, char *actions);
void HR_PL_del_action(SV* objref, SV *hashref);
HREG_API_INTERNAL
void HR_add_actions_real(SV *objref, HR_Action *actions);

//Specific implementation for Hash::Registry
void HR_impl_value_init(SV *vobj, SV *reverse);
void HR_impl_key_init(SV *keyobj, SV *forward_table, SV *scalar_lookup,
                      char *scalar_key);

void HR_impl_value_init_a(SV* vobj, SV* attrhash);

#endif