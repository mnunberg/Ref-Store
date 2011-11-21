#include "hreg.h"
#include <perl.h>
#include <string.h>
#include <stdarg.h>


#define REF2HASH(ref) ((HV*)(SvRV(ref)))

#define HR_HKEY_RLOOKUP "reverse"
#define HR_HKEY_FLOOKUP "forward"
#define HR_HKEY_SLOOKUP "scalar_lookup"

enum {
    HR_HKEY_LOOKUP_NULL = 0,
    HR_HKEY_LOOKUP_SCALAR = 1,
    HR_HKEY_LOOKUP_FORWARD = 2,
    HR_HKEY_LOOKUP_REVERSE = 3,
};

typedef char* HSpec[2];

static HSpec LookupKeys[] = {
    {HR_HKEY_SLOOKUP, (char*)sizeof(HR_HKEY_SLOOKUP)-1},
    {HR_HKEY_FLOOKUP, (char*)sizeof(HR_HKEY_FLOOKUP)-1},
    {HR_HKEY_RLOOKUP, (char*)sizeof(HR_HKEY_RLOOKUP)-1}
};

typedef char hrk_simple;
typedef struct hrk_encap_S hrk_encap;

struct hrk_encap_S {
    SV* obj_ptr;
    SV* table;
    char *obj_paddr;
};


static inline HV*
get_v_hashref(hrk_encap *ke, SV* value);

static inline void
get_hashes(HV *table, ...);

static void k_encap_cleanup(SV *ksv)
{
    /*Find our forward entry from the stringified object pointer*/
    hrk_encap *ke = (hrk_encap*)SvPV_nolen(ksv);
    HR_DEBUG("Hi!");
    HV *table;
#ifdef HR_MAKE_PARENT_RV
    if(!SvROK(ke->table)) {
        warn("Is table being destroyed?");
    }
    table = (HV*)SvRV(ke->table);
#else
    table = (HV*)ke->table;
#endif
    SV *scalar_lookup, *forward, *reverse;
    
    get_hashes(table,
               HR_HKEY_LOOKUP_REVERSE, &reverse,
               HR_HKEY_LOOKUP_FORWARD, &forward,
               HR_HKEY_LOOKUP_SCALAR, &scalar_lookup,
               HR_HKEY_LOOKUP_NULL
    );
    
    if(!(scalar_lookup && forward && reverse)) {
        die("Uhh...");
    }
    
    if( (!ke->obj_ptr) || (!SvROK(ke->obj_ptr))) {
        HR_DEBUG("Object has been deleted.");
    } else {
        HR_DEBUG("Freeing magic triggers on encapsulated object");
        HR_PL_del_action(ke->obj_ptr, scalar_lookup);
        HR_PL_del_action(ke->obj_ptr, forward);
        HR_DEBUG("Done!");
    }
    
    /*Perform the deletion manually*/
    mk_ptr_string(obj_s, ke->obj_paddr);
    HR_DEBUG("obj_s=%s", obj_s);
    
    SV **stored = NULL;
    stored = hv_fetch( REF2HASH(forward), obj_s, strlen(obj_s), 0);
    if(!stored) {
        HR_DEBUG("Can't find stored value in forward table");
        return;
    }
    
    mk_ptr_string(stored_s, SvRV(*stored));
    mk_ptr_string(ksv_s, SvRV(ksv));
    SV **stored_reverse;
    HR_DEBUG("stored_s=%s", stored_s);
    stored_reverse = hv_fetch( REF2HASH(reverse), stored_s, strlen(stored_s), 0);
    
    if(stored_reverse) {
        hv_delete( REF2HASH(*stored_reverse), ksv_s, strlen(ksv_s), G_DISCARD);
        
        SV* reverse_count = hv_scalar(REF2HASH(*stored_reverse));
                
        if(!SvTRUE(reverse_count)) {
            HR_DEBUG("Removing value's reverse hash");
            hv_delete( REF2HASH(reverse), stored_s, strlen(stored_s), G_DISCARD);
            HR_PL_del_action(*stored, reverse);
        }
    } else {
        HR_DEBUG("Can't find anything!");
    }
    
    hv_delete( REF2HASH(scalar_lookup), obj_s, strlen(obj_s), G_DISCARD);
    hv_delete( REF2HASH(forward), obj_s, strlen(obj_s), G_DISCARD );
    SvREFCNT_dec(ke->obj_ptr);
    ke->obj_ptr = NULL;
    HR_DEBUG("Returning...");
}

void HRXSK_encap_weaken(SV *ksv_ref)
{
    hrk_encap *ke = (hrk_encap*)SvPV_nolen(SvRV(ksv_ref));
    HR_DEBUG("Weakening encapsulated object reference");
    sv_rvweaken(ke->obj_ptr);
    HR_DEBUG("OK=%d", SvROK(ke->obj_ptr));
}

UV HRXSK_encap_kstring(SV* ksv_ref)
{
    hrk_encap *ke = (hrk_encap*)SvPV_nolen(SvRV(ksv_ref));
    return (UV)SvRV(ke->obj_ptr);
}

SV *HRXSK_encap_getencap(SV *ksv_ref)
{
    hrk_encap *ke = (hrk_encap*)SvPV_nolen(SvRV(ksv_ref));
    newSVsv(ke->obj_ptr);
}

SV* HRXSK_encap_new(char *package, SV* object, SV *table, SV* forward, SV* scalar_lookup)
{
    hrk_encap new_ke;
    HR_DEBUG("Encap key");
    new_ke.obj_ptr = newRV_inc(SvRV(object));
    
    new_ke.obj_paddr = SvRV(object);
    
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
    
    
    hrk_encap *keptr = (hrk_encap*)SvPV_nolen(SvRV(ksv));
    HR_DEBUG("Extracted blob..");
    
    mk_ptr_string(key_s, SvRV(object));
    HR_DEBUG("Have string key %s", key_s);
    HR_DEBUG("Scalar lookup: %p", scalar_lookup);
    
    SV *self_hval = newSVsv(ksv);
    sv_rvweaken(self_hval);
    hv_store( REF2HASH(scalar_lookup), key_s, strlen(key_s), self_hval, 0);
    
    HR_Action encap_actions[] = {
        {
            .ktype = HR_KEY_TYPE_PTR,
            .key = (char*)SvRV(object),
            .atype = HR_ACTION_TYPE_DEL_HV,
            .hashref = scalar_lookup
        },
        HR_ACTION_LIST_TERMINATOR
    };
    
    /*Call our version of DESTROY*/
    HR_DEBUG("k_encap_cleanup=%p", &k_encap_cleanup);
    HR_Action key_actions[] = {
        {
            .ktype = HR_KEY_TYPE_PTR,
            .atype = HR_ACTION_TYPE_CALL_CFUNC,
            .key = (char*)SvRV(ksv),
            .hashref = (SV*)&k_encap_cleanup,
        },
        HR_ACTION_LIST_TERMINATOR
    };
    
    HR_add_actions_real(object, encap_actions);
    HR_add_actions_real(ksv, key_actions);
    HR_DEBUG("Returning key %p", SvRV(ksv));
    return ksv;
}

static inline void
get_hashes(HV *table, ...)
{
    va_list ap;
    va_start(ap, table);
    
    while(1) {
        int ltype = (int)va_arg(ap, int);
        if(!ltype) {
            break;
        }
        SV **hashptr = (SV**)va_arg(ap, SV**);
        
        HSpec *kspec = (HSpec*)LookupKeys[ltype-1];
        char *hkey = (*kspec)[0];
        int klen = (*kspec)[1];
        SV **result = hv_fetch(table, hkey, klen, 0);
        
        if(!result) {
            *hashptr = NULL;
        } else {
            *hashptr = *result;
        }
    }
    va_end(ap);
}

static inline HV*
get_v_hashref(hrk_encap *ke, SV* value)
{
    HV *table;
#ifdef HR_MAKE_PARENT_RV
    table = (HV*)SvRV(ke->table);
#else
    table = (HV*)ke->table;
#endif
    SV *reverse;
    get_hashes(table,
               HR_HKEY_LOOKUP_REVERSE, &reverse,
               HR_HKEY_LOOKUP_NULL);
    
    if(!reverse) {
        return NULL;
    }
    
    HR_DEBUG("Have reverse!");
    mk_ptr_string(vstring, SvRV(value));
    SV **privhash = hv_fetch(REF2HASH(reverse), vstring, strlen(vstring), 0);
    if(privhash) {
        return SvRV(*privhash);
    } else {
        HR_DEBUG("Can't get privhash from hv_fetch");
        return NULL;
    }
}

void HRXSK_encap_link_value(SV *self, SV *value)
{
    HR_DEBUG("LINK VALUE!");
    hrk_encap *ke = (hrk_encap*)SvPV_nolen(SvRV(self));
    HR_DEBUG("Have key!");
    HV *v_hashref = get_v_hashref(ke, value);
    HR_DEBUG("Have private hashref");
    if(!v_hashref) {
        die("Couldn't get reverse entry!");
    }
    
    SV* hashref_ptr = newRV_inc(v_hashref);
    
    HR_Action vdel_actions[] = {
        {
            .ktype = HR_KEY_TYPE_PTR,
            .atype = HR_ACTION_TYPE_DEL_HV,
            .key   = SvRV(ke->obj_ptr),
            .flags = HR_FLAG_HASHREF_WEAKEN,
            .hashref = hashref_ptr,
        },
        HR_ACTION_LIST_TERMINATOR
    };
    HR_add_actions_real(ke->obj_ptr, vdel_actions);
    HR_DEBUG("VLINK Done!");
    
    /*If we are not truly keeping an SV but an actual HV, then we only need
     a valid reference for the add_actions() call, but don't actually need
     to keep it hanging around*/
#ifndef HR_MAKE_PARENT_RV
    SvREFCNT_dec(hashref_ptr);
#endif
}
////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////
/// Scalar Key Functions                                                     ///
////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////

#define strkey_from_simple(sp) \
    (char*)((sp)+sizeof(hrk_simple));

SV* HRXSK_new(char *package, char *key, SV *forward, SV *scalar_lookup)
{
    hrk_simple newkey;
    
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