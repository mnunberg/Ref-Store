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
        if(_hashref_eq(cur->hashref, hashref)) {
            return cur;
        }
    }
    return NULL;
}

HREG_API_INTERNAL void
HR_add_action(HR_Action *action_list,
              char *key,
              HR_KeyType_t ktype,
              SV *hashref,
              int want_unique
              )
{
    HR_Action *cur = NULL, *last = action_list;
    HR_DEBUG("hashref=%p, action_list=%p", hashref, action_list);
    
    if(action_list->ktype == HR_KEY_TYPE_NULL) {
        HR_DEBUG("List empty, creating new");
		cur = action_list;
        goto GT_INSERT_ENTRY;
    } else if( (cur = action_find_similar(action_list, hashref, &last)) ) {
        HR_DEBUG("Existing action found for %p", cur->hashref);
        return;
    }
    
    Newxz(cur, 1, HR_Action);
    HR_DEBUG("cur is now %p", cur);
    last->next = cur;
    
    GT_INSERT_ENTRY:
    HR_DEBUG("cur=%p", cur);
    cur->ktype = ktype;
    switch (ktype) {
        case HR_KEY_TYPE_PTR:
            HR_DEBUG("Found pointer key type=%p", key);
        //case HR_KEY_TYPE_PV:
            cur->key = key;
            break;
        case HR_KEY_TYPE_STR:
            HR_DEBUG("Found string type");
            Newx(cur->key, strlen(key)+1, char);
            *(cur->key) = '\0';
            strcpy(cur->key, key);
            break;
        default:
            die("Only pointer and string keys are supported!");
            break;
    }
    
    HR_DEBUG("Done assigning key");
    if(!(cur->hashref = newSVsv(hashref))) {
        die("Couldn't get new SV!");
    }
    
    HR_DEBUG("Copied hashref SV");
    //sv_rvweaken(cur->hashref);
    HR_DEBUG("Returning..");
}

HREG_API_INTERNAL
HR_Action*
HR_free_action(HR_Action *action)
{
    HR_Action *ret = action->next;
    
    if(action->ktype == HR_KEY_TYPE_STR) {
        Safefree(action->key);
    }
    if(action->hashref) {
        SvREFCNT_dec(action->hashref);
    }
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
    HV *hash = NULL;
    HR_Action *ret = action_list->next;
    
    if(!action_list->hashref) {
        HR_DEBUG("Can't find hashref!");
        goto GT_ACTION_FREE;
    }
    
    if(!(_xv_deref_complex_ok(action_list->hashref, hash, HV))) {
        HR_DEBUG("Can't extract HV from %p", action_list->hashref);
        SvREFCNT_dec(action_list->hashref);
        goto GT_ACTION_FREE;
    }
    
    switch (action_list->ktype) {
        case HR_KEY_TYPE_PTR: {
            char ptr_s[20] = { '\0' };
            sprintf(ptr_s, "%lu", action_list->key);
            HR_DEBUG("Clearing stringified pointer %s", ptr_s);
            hv_delete(hash, ptr_s, strlen(ptr_s), G_DISCARD);
            break;
        }
        case HR_KEY_TYPE_STR:
            HR_DEBUG("Removing string key=%s", action_list->key);
            hv_delete(hash, action_list->key,
                      strlen(action_list->key), G_DISCARD);
            Safefree(action_list->key);
            break;
        default:
            die("Unhandled key type!");
            break;
    }
    
    HR_DEBUG("Decrementing reference count for hashref");
    SvREFCNT_dec(action_list->hashref);
    
    GT_ACTION_FREE:
    Safefree(action_list);
	return ret;
}
