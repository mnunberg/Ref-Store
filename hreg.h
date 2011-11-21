#ifndef HREG_H_
#define HREG_H_

#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"
#include <stdint.h>

//#define HR_DEBUG

#ifndef HR_DEBUG
#define HR_DEBUG(fmt, ...) if(getenv("HR_DEBUG")) { \
    fprintf(stderr, "[%s:%d (%s)] " fmt "\n", \
        __FILE__, __LINE__, __func__, ## __VA_ARGS__); \
}
#endif

#define _hashref_eq(r1, r2) \
    (SvROK(r1) && SvROK(r2) && \
    SvRV(r1) == SvRV(r2))

#define _xv_deref_complex_ok(ref, target, to) (SvROK(ref) && SvTYPE(target=(to*)SvRV(ref)) == SVt_PV ## to)

#define _sv_deref_mg_ok(ref, target) (SvROK(ref) && SvTYPE(target=SvRV(ref)) == SVt_PVMG)

#define _mg_action_list(mg) (HR_Action*)mg->mg_ptr

#define mk_ptr_string(vname, ptr) \
    char vname[20] = { '\0' }; \
    sprintf(vname, "%lu", ptr);


//#define HR_MAKE_PARENT_RV

#define HREG_API_INTERNAL

typedef enum {
    HR_ACTION_TYPE_NULL         = 0,
    HR_ACTION_TYPE_DEL_AV       = 1,
    HR_ACTION_TYPE_DEL_HV       = 2,
    HR_ACTION_TYPE_CALL_CV      = 3,
    HR_ACTION_TYPE_CALL_CFUNC   = 4,
} HR_ActionType_t;

typedef enum {
    HR_KEY_TYPE_NULL= 0,
    HR_KEY_TYPE_PTR = 1,
    HR_KEY_TYPE_STR = 2
} HR_KeyType_t;

typedef enum {
    HR_ACTION_NOT_FOUND,
    HR_ACTION_DELETED,
    HR_ACTION_EMPTY
} HR_DeletionStatus_t;

enum {
    HR_FLAG_STR_NO_ALLOC =      1 << 0,
    HR_FLAG_HASHREF_WEAKEN =    1 << 1
};

typedef struct HR_Action HR_Action;
typedef void(*HR_ActionCallback)(void*);

struct
__attribute__((__packed__))
HR_Action {
    HR_Action   *next;
    char        *key;
    
    //Action type and union
    unsigned int atype:3;
    
    //TODO: Implement the unions
    
    //union {
    //    SV *hashref;
    //    SV *arrayref;
    //    HR_ActionCallback *cb;
    //} u_action;
    
    //Key type and union
    unsigned int ktype:2;
    
    //union {
    //    unsigned int idx;
    //    void *ptr;
    //    char *key;
    //} u_selector;
    
    SV          *hashref;
    
    unsigned int flags:2;
    /*TODO:
     instead of just using a hashref, specify an action type, perhaps deleting
     something from an arrayref or calling a subroutine directly
    */
};

#define HR_ACTION_LIST_TERMINATOR \
{ NULL, NULL, HR_KEY_TYPE_NULL, HR_ACTION_TYPE_NULL, 0, 0 }

HREG_API_INTERNAL
void HR_add_action(HR_Action *action_list, HR_Action *new_action, int want_unique);

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
HREG_API_INTERNAL
void HR_add_actions_real(SV *objref, HR_Action *actions);

/*Perl API*/

void HR_PL_add_actions(SV* objref, char *actions);
void HR_PL_del_action(SV* objref, SV *hashref);
void HR_PL_add_action_ptr(SV *objref, SV *hashref);
void HR_PL_add_action_str(SV *objref, SV *hashref, const char *key);

SV*  HRXSK_new(char *package, char *key, SV *forward, SV *scalar_lookup);
char *HRXSK_kstring(SV* self);

SV* HRXSK_encap_new(char *package, SV *encapsulated_object,
                    SV *table, SV *forward, SV *scalar_lookup);

UV HRXSK_encap_kstring(SV *ksv_ref);
void HRXSK_encap_weaken(SV *ksv_ref);
void HRXSK_encap_link_value(SV *self, SV *value);

/*New key object..*/


#endif /*HREG_H_*/
