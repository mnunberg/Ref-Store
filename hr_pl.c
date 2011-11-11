#include <string.h>
#include <perl.h>
#include <stdint.h>
#include "hreg.h"



/*predecl*/
static inline MAGIC* get_our_magic(SV* objref, int create);
static inline void free_our_magic(SV* objref);
static int freehook(pTHX_ SV* target, MAGIC *mg);

static MGVTBL vtbl = { .svt_free = &freehook };

static int
freehook(pTHX_ SV* target, MAGIC *mg)
{
	HR_DEBUG("FREEHOOK: mg=%p, obj=%p", mg, target);
    HR_trigger_and_free_actions(_mg_action_list(mg));
}



static inline MAGIC*
get_our_magic(SV* objref, int create)
{
	MAGIC *mg;
	//SV *action_list;
    
    HR_Action *action_list;
    SV *target;
    
    if(!SvROK(objref)) {
        die("Value=%p must be a reference type", objref);
    }
    
    target = SvRV(objref);
    
    objref = NULL; /*Don't use this anymore*/
    
	if(SvTYPE(target) < SVt_PVMG) {
		HR_DEBUG("Object=%p is not yet magical!", target);
		if(create) {
			goto GT_NEW_MAGIC;
		} else {
			HR_DEBUG("No magic found, but creation not requested");
			return NULL;
		}
	}
	
	HR_DEBUG("Will try to locate existing magic");
	mg = mg_find(target, PERL_MAGIC_ext);
	if(mg) {
		HR_DEBUG("Found initial mg=%p", mg);
	} else {
		HR_DEBUG("Can't find existing magic!");
	}
	for(; mg; mg = mg->mg_moremagic) {
		
		HR_DEBUG("Checking mg=%p", mg);
		if(mg->mg_virtual == &vtbl) {
			return mg;
		}
	}
	
	if(!create) {
		return NULL;
	}
	
	GT_NEW_MAGIC:
	HR_DEBUG("Creating new magic for %p", target);
    Newxz(action_list, 1, HR_Action);
	mg = sv_magicext(target, target, PERL_MAGIC_ext, &vtbl,
					 (const char*)action_list, 0);
    
	if(!mg) {
		die("Couldn't create magic!");
	} else {
		HR_DEBUG("Created mg=%p, alist=%p", mg, action_list);
	}
	return mg;
}

static inline void
free_our_magic(SV* target)
{    
    MAGIC *mg_last = mg_find(target, PERL_MAGIC_ext);
    MAGIC *mg_cur = mg_last;
	
    for(;mg_cur; mg_last = mg_cur, mg_cur = mg_cur->mg_moremagic
        ) {
		if(mg_cur->mg_virtual == &vtbl) {
			break;
		}
	}
	
    if(!mg_cur) {
        return;
    }
    
    HR_Action *action = _mg_action_list(mg_cur);
    if(!action) {
		warn("Found action=%p", action);
		while((action = HR_free_action(action)));
	}
    
    /*Check if this is the last magic on the variable*/
    GT_FREE_MAGIC:
	mg_cur->mg_virtual = NULL;
    if(mg_cur == mg_last) {
        /*First magic entry*/
        HR_DEBUG("Calling sv_unmagic");
        sv_unmagic(mg_cur->mg_obj, PERL_MAGIC_ext);
		HR_DEBUG("Done!");
    } else {
        mg_last->mg_moremagic = mg_cur->mg_moremagic;
		HR_DEBUG("About to Safefree(mg_cur=%p)", mg_cur);
		HR_DEBUG("Free=%p", mg_cur);
        Safefree(mg_cur);
    }    
}

HREG_API_INTERNAL void
HR_add_actions_real(SV* objref, HR_Action *actions)
{
    HR_DEBUG("Have objref=%p, action_list=%p", objref, actions);
    MAGIC *mg = get_our_magic(objref, 1);
    
    if(!actions) {
        die("Must have at least one action!");
    }
    
    while(actions->ktype) {
        HR_DEBUG("ADD: T=%d, K=%p, H=%p", actions->ktype, actions->key,
                 actions->hashref);
        if(!actions->hashref) {
            die("Must have hashref!");
        }
        HR_add_action(_mg_action_list(mg), actions->key, actions->ktype,
                      actions->hashref, 1);
        actions++;
    }
}

void
HR_PL_add_actions(SV *objref, char *blob) {
    add_actions_real(objref, (HR_Action*)blob);
}

void
HR_PL_del_action(SV* objref, SV* hashref)
{
	MAGIC *mg = get_our_magic(objref, 0);
    HR_DEBUG("DELETE: O=%p, SV=%p", objref, hashref);
	if(!mg) {
		return;
	}
    int dv = HR_ACTION_NOT_FOUND;
    
    while( (dv = HR_del_action(_mg_action_list(mg), hashref)) == HR_ACTION_DELETED );
    /*no body*/
    
    if(dv == HR_ACTION_EMPTY) {
        free_our_magic(SvRV(objref));
    }
    
}

