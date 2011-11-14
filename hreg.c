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
*action_find_similar(HR_Action *actions, SV *hashref, HR_Action **lastp);

static inline HR_Action*
trigger_and_free_action(HR_Action *action_list);


////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////
/// Definitions                                                              ///
////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////

static inline HR_Action* action_find_similar(HR_Action *action_list,
                                             SV* hashref, HR_Action **lastp)
{
    HR_Action *cur = action_list;
    *lastp = cur;
    for(; cur; *lastp = cur, cur = cur->next) {
		
#ifdef HR_MAKE_PARENT_RV
        if(_hashref_eq(cur->hashref, hashref)) {
            return cur;
        }
#else
		if(cur->hashref == SvRV(hashref)) {
			return cur;
		}
#endif

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
			action_list, new_action->hashref, &last)) ) {
		
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
				*(cur->key) = '\0';
				strcpy(cur->key, new_action->key);
			}
            break;
        default:
            die("Only pointer and string keys are supported!");
            break;
    }
    
    HR_DEBUG("Done assigning key");
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

    HR_DEBUG("Copied hashref SV");
    HR_DEBUG("Returning..");
}

HREG_API_INTERNAL
HR_Action*
HR_free_action(HR_Action *action)
{
    HR_Action *ret = action->next;
    
    if(action->ktype == HR_KEY_TYPE_STR) {
		if(action->flags & HR_FLAG_STR_NO_ALLOC == 0) {
			HR_DEBUG("NO_ALLOC unset");
			Safefree(action->key);
		}
    }

#ifdef HR_MAKE_PARENT_RV
    if(action->hashref) {
        SvREFCNT_dec(action->hashref);
    }
#endif
    Safefree(action);
    return ret;
}

HREG_API_INTERNAL
HR_DeletionStatus_t
HR_del_action(HR_Action *action_list, SV *hashref)
{
    HR_Action *cur = action_list, *last = action_list;
    int ret;
    
    if(cur->next == NULL && cur->hashref == hashref) {
        cur->hashref = NULL;
        return HR_ACTION_NOT_FOUND;
    }
	cur = action_find_similar(action_list, hashref, &last);
	
	if(!cur) {
		return HR_ACTION_NOT_FOUND;
	}
    
	if((!cur->next) && cur == action_list) {
		return HR_ACTION_EMPTY;
	} else {
		last->next = cur->next;
        HR_free_action(cur);
	}
    
	return HR_ACTION_DELETED;
}

HREG_API_INTERNAL
void
HR_trigger_and_free_actions(HR_Action *action_list)
{
    HR_DEBUG("BEGIN action_list=%p, next=%p", action_list,
             action_list->next);
    HR_Action *last;
	while(action_list)
    while( (action_list = trigger_and_free_action(action_list)) );
}


static inline HR_Action*
trigger_and_free_action(HR_Action *action_list)
{
    HR_Action *ret = action_list->next;
    
    if(!action_list->hashref) {
        HR_DEBUG("Can't find hashref!");
        goto GT_ACTION_FREE;
    }
    
#ifdef HR_MAKE_PARENT_RV
    HV *hash = NULL;
    if(!(_xv_deref_complex_ok(action_list->hashref, hash, HV))) {
        HR_DEBUG("Can't extract HV from %p", action_list->hashref);
        SvREFCNT_dec(action_list->hashref);
        goto GT_ACTION_FREE;
    }
#endif

    switch (action_list->ktype) {
        case HR_KEY_TYPE_PTR: {
			if(action_list->atype == HR_ACTION_TYPE_DEL_HV) {
				mk_ptr_string(ptr_s, action_list->key);
				HR_DEBUG("Clearing stringified pointer %s", ptr_s);
#ifdef HR_MAKE_PARENT_RV
				hv_delete(hash, ptr_s, strlen(ptr_s), G_DISCARD);
#else
				hv_delete((HV*)action_list->hashref, ptr_s, strlen(ptr_s), G_DISCARD);
#endif
			} else if (action_list->atype == HR_ACTION_TYPE_CALL_CFUNC) {
				void (*fp)(char*) = action_list->hashref;
				fp(action_list->key);
			} else {
				die("Unsupported action %d", action_list->atype);
			}
            break;
        }
        case HR_KEY_TYPE_STR:
            HR_DEBUG("Removing string key=%s", action_list->key);
#ifdef HR_MAKE_PARENT_RV
            hv_delete(hash, action_list->key,
                      strlen(action_list->key), G_DISCARD);
#else
			hv_delete((HV*)action_list->hashref, action_list->key,
					  strlen(action_list->key), G_DISCARD);
#endif
			
			if(action_list->flags & HR_FLAG_STR_NO_ALLOC == 0) {
				HR_DEBUG("Freeing allocated key");
				Safefree(action_list->key);
			} else {
				HR_DEBUG("Not freeing unallocated key");
			}
            break;
        default:
            die("Unhandled key type!");
            break;
    }

#ifdef HR_MAKE_PARENT_RV
    HR_DEBUG("Decrementing reference count for hashref");
    SvREFCNT_dec(action_list->hashref);
#endif

    GT_ACTION_FREE:
    Safefree(action_list);
	return ret;
}
