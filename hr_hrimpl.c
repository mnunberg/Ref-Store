#include "hreg.h"
#include <perl.h>
#include <string.h>

#define REF2HASH(ref) ((HV*)(SvRV(ref)))

static struct
hr_key_simple {
    //SV *forward_hashref;
    //SV *scalar_hashref;
    /*implicitly allocated string follows..*/
};

static struct
hr_key_encapsulating {
    SV* obj_ptr;
    SV* table;
};

static inline HV*
get_v_hashref(struct hr_key_encapsulating *ke, SV* value);

static void k_encap_cleanup(SV *ksv)
{
    /*Find our forward entry from the stringified object pointer*/
    struct hr_key_encapsulating *ke = SvPV_nolen(ksv);
    
    HV *table;
#ifdef HR_MAKE_PARENT_RV
    if(!SvROK(ke->table)) {
        warn("Is table being destroyed?");
    }
    table = SvRV(ke->table);
#else
    table = ke->table;
#endif
    
    SV **scalar_lookup = hv_fetch(table, "scalar_lookup", 0, 0);
    SV **forward        = hv_fetch(table, "forward", 0, 0);
    SV **reverse        = hv_fetch(table, "reverse", 0, 0);
    if(!(scalar_lookup && forward && reverse)) {
        die("Uhh...");
    }
    if(!SvROK(ke->obj_ptr)) {
        die("This key should not exist when encapsulated object has been deleted");
    }
    
    HR_PL_del_action(ke->obj_ptr, *scalar_lookup);
    HR_PL_del_action(ke->obj_ptr, *forward);
    
    /*Perform the deletion manually*/
    mk_ptr_string(obj_s, SvRV(ke->obj_ptr));
    SV **stored = hv_delete( REF2HASH(*forward), obj_s, 0, 0);
    if(!stored) {
        return;
    }    
    mk_ptr_string(stored_s, SvRV(*stored));
    mk_ptr_string(ksv_s, SvRV(ksv));
    
    SV **stored_reverse = hv_fetch( REF2HASH(*reverse), stored_s, 0, 0);
    hv_delete( REF2HASH(*scalar_lookup), obj_s, 0, G_DISCARD);
    hv_delete( REF2HASH(*stored_reverse), ksv_s, 0, G_DISCARD);
    
    if(!hv_scalar( REF2HASH(*stored_reverse) )) {
        hv_delete( REF2HASH(*reverse), stored_s, 0, G_DISCARD);
        HR_PL_del_action(*stored, *reverse);
    }
}

void HRXSK_encap_weaken(SV *ksv_ref)
{
    struct hr_key_encapsulating *ke = SvPV_nolen(SvRV(ksv_ref));
    sv_rvweaken(ke->obj_ptr);
}

UV HRXSK_encap_kstring(SV* ksv_ref)
{
    struct hr_key_encapsulating *ke = SvPV_nolen(SvRV(ksv_ref));
    return SvRV(ke->obj_ptr);
}

SV* HRXSK_encap_new(char *package, SV* object, SV *table, SV* forward, SV* scalar_lookup)
{
    struct hr_key_encapsulating new_ke;
    HR_DEBUG("Encap key");
    new_ke.obj_ptr = newSVsv(object);
    
#ifdef HR_MAKE_PARENT_RV
    new_ke.table = newSVsv(table);
#else
    new_ke.table = SvRV(table);
#endif
    HR_DEBUG("Have table");
    SV *ksv = sv_setref_pvn(newSV(0),
                            package,
                            (char*)&new_ke, sizeof(new_ke));
    HR_DEBUG("New blessed class");
    
    
    struct hr_key_encapsulating *keptr = SvPV_nolen(SvRV(ksv));
    HR_DEBUG("Extracted blob..");
    
    mk_ptr_string(key_s, SvRV(object));
    HR_DEBUG("Have string key %s", key_s);
    HR_DEBUG("Scalar lookup: %p", scalar_lookup);
    
    SV *self_hval = newSVsv(ksv);
    sv_rvweaken(self_hval);
    hv_store(((HV*)SvRV(scalar_lookup)),
                               key_s, strlen(key_s), self_hval, 0);
    
    HR_Action encap_actions[] = {
        {
            .ktype = HR_KEY_TYPE_PTR,
            .key = SvRV(object),
            .atype = HR_ACTION_TYPE_DEL_HV,
            .hashref = scalar_lookup
        },
        HR_ACTION_LIST_TERMINATOR
    };
    
    /*Call our version of DESTROY*/
    HR_Action key_actions[] = {
        {
            .ktype = HR_KEY_TYPE_PTR,
            .atype = HR_ACTION_TYPE_CALL_CFUNC,
            .key = SvRV(ksv),
            .hashref = k_encap_cleanup,
        },
        HR_ACTION_LIST_TERMINATOR
    };
    
    HR_add_actions_real(object, encap_actions);
    HR_add_actions_real(ksv, key_actions);
    HR_DEBUG("Returning key %p", SvRV(ksv));
    return ksv;
}

static inline HV*
get_v_hashref(struct hr_key_encapsulating *ke, SV* value)
{
    SV **reverse = hv_fetch((HV*)(SvRV(ke->table)), "reverse", 0, 0);
    if(!reverse) {
        return NULL;
    }
    mk_ptr_string(vstring, SvRV(value));
    SV **privhash = hv_fetch(REF2HASH(*reverse), vstring, 0, 0);
    if(privhash) {
        return *privhash;
    } else {
        return NULL;
    }
}

void HRXSK_encap_link_value(SV *self, SV *value)
{
    HR_DEBUG("LINK VALUE!");
    struct hr_key_encapsulating *ke = SvPV_nolen(SvRV(self));
    HR_DEBUG("Have key!");
    HV *v_hashref = get_v_hashref(ke, value);
    if(!v_hashref) {
        die("Couldn't get reverse entry!");
    }
    HR_Action vdel_actions[] = {
        {
            .ktype = HR_KEY_TYPE_PTR,
            .atype = HR_ACTION_TYPE_DEL_HV,
            .key   = SvRV(ke->obj_ptr),
            .flags = HR_FLAG_HASHREF_WEAKEN,
            .hashref = newRV_noinc(v_hashref)
        },
        HR_ACTION_LIST_TERMINATOR
    };
    HR_add_actions_real(ke->obj_ptr, vdel_actions);
}
////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////
/// Scalar Key Functions                                                     ///
////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////

#define strkey_from_simple(sp) \
    (char*)((sp)+sizeof(struct hr_key_simple));

SV* HRXSK_new(char *package, char *key, SV *forward, SV *scalar_lookup)
{
    struct hr_key_simple newkey = {
        //.forward_hashref = SvRV(forward),
        //.scalar_hashref = SvRV(scalar_lookup)
    };
    
    int keylen = strlen(key) + 1;
    int bloblen = keylen + sizeof(newkey);
    
    char blob[bloblen];
    memcpy(blob, &newkey, sizeof(newkey));
    memcpy((char*)(blob+sizeof(newkey)), key, keylen);
    
    SV *ksv = sv_setref_pvn(newSV(0), package, blob, bloblen);
    
    char *blob_alloc = SvPV_nolen(SvRV(ksv));
    char *key_offset = blob_alloc + sizeof(newkey);
        
    SV **scalar_entry = hv_store(SvRV(scalar_lookup),
                                 key, keylen-1,
                                 newSVsv(ksv), 0);
    if(!scalar_entry) {
        die("Couldn't add entry!");
    }
    sv_rvweaken(*scalar_entry);
    
    HR_Action actions[] = {
        {
            .ktype = HR_KEY_TYPE_STR,
            .key = key_offset,
            .hashref = scalar_lookup,
            .atype = HR_ACTION_TYPE_DEL_HV,
            .flags = HR_FLAG_STR_NO_ALLOC
        },
        {
            .ktype = HR_KEY_TYPE_STR,
            .key = key_offset,
            .hashref = forward,
            .atype = HR_ACTION_TYPE_DEL_HV,
            .flags = HR_FLAG_STR_NO_ALLOC
        },
        HR_ACTION_LIST_TERMINATOR
    };
    
    HR_add_actions_real(ksv, actions);
    return ksv;
}

char * HRXSK_kstring(SV *obj)
{
    char *blob = SvPV_nolen(SvRV(obj));
    char *ret = strkey_from_simple(blob);
    HR_DEBUG("Requested key=%s", ret);
    return ret;
}