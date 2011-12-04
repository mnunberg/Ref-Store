#include "hreg.h"
#include <perl.h>


////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////
/// Internal Predeclarations                                                 ///
////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////
static inline HR_Action
*action_find_similar(HR_Action *actions, SV *hashref,
                     void *key, HR_KeyType_t ktype,
                     HR_Action **lastp);

static inline HR_Action*
trigger_and_free_action(HR_Action *action_list, SV *object);

static inline void action_sanitize_str(HR_Action *action);
static inline void action_sanitize_ptr(HR_Action *action);

#define action_clear(actionp) \
    actionp->flags = actionp->ktype = actionp->key = actionp->hashref = 0;


#define action_sanitize(actionp) \
    ((actionp->ktype == HR_KEY_TYPE_STR) \
            ? action_sanitize_str(actionp) : \
            action_sanitize_ptr(actionp)); \
    action_clear(actionp);

////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////
/// Definitions                                                              ///
////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////

#ifndef HR_MAKE_PARENT_RV
#define cmp_container(stored_container, uspec) \
    (SvROK(uspec) && (stored_container == SvRV(uspec)))
#else
#define cmp_container _hashref_eq \
    (SvROK(stored_container) \
    && SvROK(uspec) \
    && SvRV(container) == SvRV(uspec))
#endif

static inline void action_sanitize_str(HR_Action *action)
{
    if( (action->flags & HR_FLAG_STR_NO_ALLOC == 0 ) ) {
        Safefree(action->key);
        action->key == NULL;
    }
}

static inline void action_sanitize_ptr(HR_Action *action)
{
    HR_DEBUG("Called!");
    if( (action->flags & HR_FLAG_SV_REFCNT_DEC) ) {
        HR_DEBUG("Decreasing reference count on SV=%p", action->key);
        SvREFCNT_dec((SV*)action->key);
        action->key = NULL;
    } else {
        HR_DEBUG("Flags=%d", action->flags);
    }
}


static inline HR_Action* action_find_similar(
    HR_Action *action_list,
    SV* hashref, void *key, HR_KeyType_t ktype,
    HR_Action **lastp)
{
    HR_DEBUG("Request to find ktype=%d, kp=%p", ktype, hashref);
    HR_Action *cur = action_list;
    *lastp = cur;
    
    for(; cur; *lastp = cur, cur = cur->next) {
        
        if(action_container_is_sv(cur)) {
            HR_DEBUG("Comparing SV");
            /*Prefilter for SV comparisons*/
            if(!cmp_container(cur->hashref, hashref)) {
                continue;
            } else if(ktype == HR_KEY_TYPE_NULL) {
                return cur;
            }
        } else if(ktype == HR_KEY_TYPE_NULL) {
            if(cur->hashref == hashref) {
                return cur;
            } else {
                continue;
            }
        }
        
        switch(ktype) {
            case HR_KEY_STYPE_PTR_RV:
                if(action_key_is_rv(cur)) {
                    assert(SvROK((SV*)cur->key));
                    if(SvRV((SV*)cur->key) == (SV*)key) {
                        return cur;
                    }
                }
                break;
            case HR_KEY_TYPE_PTR:
                if((char*)key == cur->key) {
                    return cur;
                }
                break;
            case HR_KEY_TYPE_STR:
                if(strcmp((char*)key, cur->key) == 0) {
                    return cur;
                }
                break;
            default:
                die("Unknown key type %d", ktype);
                break;
        }
    }
    return NULL;
}

HREG_API_INTERNAL void
HR_add_action(HR_Action *action_list,
              HR_Action *new_action,
              int want_unique)
{
    HR_Action *cur = NULL, *last = action_list;
    HR_DEBUG("hashref=%p, action_list=%p", new_action->hashref, action_list);
    
    if(action_list->ktype == HR_KEY_TYPE_NULL) {
        HR_DEBUG("List empty, creating new");
        cur = action_list;
        goto GT_INSERT_ENTRY;
    } else if( (cur = action_find_similar(
            action_list, new_action->hashref,
            new_action->key, new_action->ktype,
            &last)) ) {
        
        HR_DEBUG("Existing action found for %p", cur->hashref);
        return;
    }
    
    Newxz(cur, 1, HR_Action);
    HR_DEBUG("cur is now %p", cur);
    last->next = cur;
    
    GT_INSERT_ENTRY:
    HR_DEBUG("cur=%p", cur);
    Copy(new_action, cur, 1, HR_Action);
    cur->next = NULL;
    
    switch (new_action->ktype) {
        case HR_KEY_TYPE_PTR:
            HR_DEBUG("Found pointer key type=%p", new_action->key);
            break;
        case HR_KEY_TYPE_STR:
            HR_DEBUG("Found string type");
            if(new_action->flags & HR_FLAG_STR_NO_ALLOC == 0) {
                Newx(cur->key, strlen(new_action->key)+1, char);
                *((char*)(cur->key)) = '\0';
                strcpy(cur->key, new_action->key);
            }
            break;
        default:
            die("Only pointer and string keys are supported!");
            break;
    }
    
    HR_DEBUG("Done assigning key");
    if(new_action->atype != HR_ACTION_TYPE_CALL_CFUNC) {
#ifdef HR_MAKE_PARENT_RV
        if(!(cur->hashref = newSVsv(new_action->hashref))) {
            die("Couldn't get new SV!");
        }
        if(new_action->flags & HR_FLAG_HASHREF_WEAKEN) {
            sv_rvweaken(cur->hashref);
        }
#else
        cur->hashref = SvRV(new_action->hashref);
#endif
    } else {
        cur->hashref = new_action->hashref;
    }
    HR_DEBUG("Flags=%d", new_action->flags);
}



HREG_API_INTERNAL
HR_Action*
HR_free_action(HR_Action *action)
{
    HR_Action *ret = action->next;
    action_sanitize(action);
#ifdef HR_MAKE_PARENT_RV
    if(action->hashref) {
        SvREFCNT_dec(action->hashref);
    }
#endif
    HR_DEBUG("Free: %p", action);
    Safefree(action);
    return ret;
}


HREG_API_INTERNAL
HR_DeletionStatus_t
HR_del_action(HR_Action *action_list, SV *hashref, void *key, HR_KeyType_t ktype)
{
    HR_Action *cur = action_list, *last = action_list;
    cur = action_find_similar(action_list, hashref, key, ktype, &last);
        
    if(!cur) {
        HR_DEBUG("Nothing to delete");
        return HR_ACTION_NOT_FOUND;
    }
    
    if(cur == action_list) {
        cur->hashref = NULL;
        return HR_ACTION_EMPTY;
    }
        
    /*First action, but there are more*/
    if(last == cur && cur->next) {
        /*Copy over next entry to the first entry, and free the *next* pointer*/
        HR_DEBUG("Shifting first action...");
        HR_Action *nextp = cur->next;
        assert(last == cur == action_list);
        action_sanitize(cur);
        Copy(nextp, last, 1, HR_Action);
        Safefree(nextp);
        return HR_ACTION_DELETED;
    } else {
        HR_DEBUG("Delete %p hashref=%p", cur, cur->hashref);
        action_sanitize(cur);
        
        last->next = cur->next;
        Safefree(cur);
    }
    return HR_ACTION_DELETED;
}

HREG_API_INTERNAL
HR_DeletionStatus_t
HR_nullify_action(HR_Action *action_list, SV *hashref, void *key, HR_KeyType_t ktype)
{
    HR_Action *last = NULL;
    
    action_list = action_find_similar(action_list, hashref, key, ktype, &last);
    if(action_list) {
        HR_DEBUG("Nullifying action");
        action_sanitize(action_list);
        return HR_ACTION_DELETED;
    }
    HR_DEBUG("Can't find action to nullify!");
    return HR_ACTION_NOT_FOUND;
}

HREG_API_INTERNAL
void
HR_trigger_and_free_actions(HR_Action *action_list, SV *object)
{
    HR_Action *head = action_list;
    HR_DEBUG("BEGIN action_list=%p, next=%p", action_list,
             action_list->next);
    HR_Action *last;
    while( (action_list = trigger_and_free_action(action_list, object)) ) { ; }
    
    /*We don't want to let each action being freed immediately. Speficially
     we want to allow a case where we can nullify existing actions, in which
     case we need the integrity of the linked list*/
    
    action_list = head;
    while(action_list) {
        last = action_list;
        action_list = action_list->next;
        HR_DEBUG("Free %p", last);
        Safefree(last);
    }
    HR_DEBUG("Done");
}

#define FAKE_REFCOUNT (1 << 16)
static inline U32
refcnt_ka_begin(SV *sv)
{
    U32 ret = SvREFCNT(sv);
    SvREFCNT(sv) = FAKE_REFCOUNT;
    return ret;
}

static inline void
refcnt_ka_end(SV *sv, U32 old_refcount)
{
    I32 effective_refcount = old_refcount + (SvREFCNT(sv) - FAKE_REFCOUNT);
    if(effective_refcount <= 0 && old_refcount > 0) {
        SvREFCNT(sv) = 1;
        SvREFCNT_dec(sv);
    } else {
        SvREFCNT(sv) = effective_refcount;
        if(effective_refcount != SvREFCNT(sv)) {
            die("Detected negative refcount!");
        }
    }
}

static inline HR_Action*
trigger_and_free_action(HR_Action *action_list, SV *object)
{
    
    static int recurse_level = 0;
    
    HR_Action *ret = NULL;
    recurse_level++;
    
    if(!action_list->hashref) {
        HR_DEBUG("Can't find hashref!");
        goto GT_ACTION_FREE;
    }
    SV *container;
#ifdef HR_MAKE_PARENT_RV
    if(!(_xv_deref_complex_ok(action_list->hashref, container, HV))) {
        warn("Can't extract HV from %p", action_list->hashref);
        SvREFCNT_dec(action_list->hashref);
        goto GT_ACTION_FREE;
    }
#else
    container = action_list->hashref;
#endif
    U32 old_refcount;
    
    HR_DEBUG("ENTER! (LVL=%d)", recurse_level);
    switch (action_list->ktype) {
        
        case HR_KEY_TYPE_NULL:
            HR_DEBUG("Action nullified!");
            goto GT_ACTION_FREE;
            break;
        
        case HR_KEY_TYPE_PTR: {
            switch (action_list->atype) {
                case HR_ACTION_TYPE_DEL_HV:
                case HR_ACTION_TYPE_DEL_AV: {
                    
                    /*Since this function can recurse, we need to ensure our
                     collection remains valid*/
                    HR_DEBUG("(KEEPALIVE): Refcount for container=%p is now %d", container, SvREFCNT(container));
                    old_refcount = refcnt_ka_begin(container);
                    
                    if(action_list->atype == HR_ACTION_TYPE_DEL_HV) {
                        if(SvTRUE(hv_scalar((HV*)container))) {
                            if( (action_list->flags & HR_FLAG_PTR_NO_STRINGIFY) ) {
                                HR_DEBUG("Deleting packed pointer %p (HV=%p)",
                                         action_list->key, container);
                                hv_delete((HV*)container, &(action_list->key),
                                          sizeof(char*), G_DISCARD);
                            } else {
                                mk_ptr_string(ptr_s, action_list->key);
                                HR_DEBUG("Clearing stringified pointer %s (HV=%p)",
                                         ptr_s, container);
                                hv_delete((HV*)container, ptr_s,
                                          strlen(ptr_s), G_DISCARD);
                            }
                        }
                    } else { /*DEL_AV*/
                        HR_DEBUG("Clearing idx=%d from AV=%p", action_list->key, container);
                        if(av_exists( (AV*)container, (UV)action_list->key )) {
                            HR_DEBUG("idx=%d exists", (UV)action_list->key);
                            sv_setsv(*(av_fetch((AV*)container, (UV)action_list->key, 1)),
                                     &PL_sv_undef);
                        }
                    }
                    
                    /*Now we want to check how much the refcount has changed*/
                    HR_DEBUG("KEEPALIVE, ORIG=%d, CUR=%d", FAKE_REFCOUNT, SvREFCNT(container));
                    refcnt_ka_end(container, old_refcount);
                    
                    break;
                }
                case HR_ACTION_TYPE_CALL_CFUNC: {
                    HR_DEBUG("Calling C Function!");
                    ((HR_ActionCallback)(action_list->hashref)) (object, action_list->key);
                    break;
                }
                
                default:
                    die("Unhandled action type=%d", action_list->atype);
                    break;
            }
            action_sanitize_ptr(action_list);
            break;
        }
        
        case HR_KEY_TYPE_STR:
            old_refcount = refcnt_ka_begin(container);
            HR_DEBUG("Removing string key=%s (A=%d)", action_list->key,
                     action_list->atype);
            hv_delete((HV*)container,
                      action_list->key, strlen(action_list->key), G_DISCARD);
            action_sanitize_str(action_list);
            refcnt_ka_end(container, old_refcount);
            
            break;
        default:
            die("Unhandled key type %d!", action_list->ktype);
            break;
    }

#ifdef HR_MAKE_PARENT_RV
    HR_DEBUG("Decrementing reference count for hashref");
    SvREFCNT_dec(action_list->hashref);
#endif

    GT_ACTION_FREE:
    ret = action_list->next;
    action_clear(action_list);
    HR_DEBUG("EXIT (LVL=%d)", recurse_level);
    recurse_level--;
    return ret;
}
