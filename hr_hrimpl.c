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
    
    SV* hashref_ptr = newRV_inc((SV*)v_hashref);
    
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
        
    SV **scalar_entry = hv_store(REF2HASH(scalar_lookup),
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


/*API*/

/*All references to other non-perl functions work in the existing PP implementation
 when they are run via their XS wrappers run via C2XS
*/
static enum {
    STORE_OPT_STRONG_KEY    = 1 << 0,
    STORE_OPT_STRONG_VALUE  = 1 << 1,
    STORE_OPT_O_CREAT       = 1 << 2
} HR_KeyOptions;

#define PKG_KEY_SCALAR "Hash::Registry::XS::Key"
#define PKG_KEY_ENCAP "Hash::Registry::XS::Key::Encapsulating"
#define STROPT_STRONG_KEY "StrongKey"
#define STROPT_STRONG_VALUE "StrongValue"

static inline SV* ukey2ikey(
    SV* self,
    SV* key,
    SV** existing,
    int options)
{
    SV *slookup = NULL, *flookup = NULL;
    SV *kobj = NULL;
    
    get_hashes(REF2HASH(self),
               HR_HKEY_LOOKUP_SCALAR, &slookup,
               HR_HKEY_LOOKUP_NULL);
    
    SV *our_key;
    
    if(SvROK(key)) {
        our_key = newSVuv(SvUV(key));
    } else {
        our_key = newSVsv(key);
    }
    
    sv_2mortal(our_key);
    HR_DEBUG("Using key %s", SvPV_nolen(our_key));
    HE *stored_key = hv_fetch_ent(REF2HASH(slookup), our_key, 0, 0);
    if(stored_key) {        
        if(existing
            && SvROK(HeVAL(stored_key))
            && SvRV(HeVAL(stored_key)) != SvRV(*existing))
        {
             die("Requested new key storage for value %p, but key is already "
                 "linked to %p", SvRV(*existing), SvRV(HeVAL(stored_key)));
        }
        else
        {
            if(existing) {
                *existing = HeVAL(stored_key);
            }
            HR_DEBUG("Found KO=%p (RV=%p)", HeVAL(stored_key), SvRV(HeVAL(stored_key)));
            HR_DEBUG("Refcount for base object: %d", SvREFCNT(SvRV(HeVAL(stored_key))));
            return HeVAL(stored_key);
        }
    } else {
        if(existing) {
            *existing = NULL;
        }
    }
    /*The previous block always returns*/
    
    if( (options & STORE_OPT_O_CREAT) == 0 ) {
        return NULL;
    }
    
    get_hashes(REF2HASH(self),
           HR_HKEY_LOOKUP_FORWARD, &flookup,
           HR_HKEY_LOOKUP_NULL);
    
    if(SvROK(key)) {
        kobj =  HRXSK_encap_new(
                PKG_KEY_ENCAP,
                key, self, flookup, slookup
        );
        
        if( (options & STORE_OPT_STRONG_KEY) == 0) {
            HRXSK_encap_weaken(kobj);
        }
    } else {
        kobj = HRXSK_new(PKG_KEY_SCALAR,
                         //No need to give our own table
                SvPV_nolen(our_key), flookup, slookup
        );
    }
    return kobj;
}

void HRA_store_sk(SV *self, SV *key, SV *value, ...)
{
    HV *table = (HV*)SvRV(self);
    
    SV *flookup = NULL, /*forward lookup*/
        *rlookup = NULL;
    
    
    SV *kobj = NULL; //Key object
    SV *kstring; //Key string or refaddr
    
    SV *existing_ent = value;
    
    SV *vstring = sv_2mortal(newSVuv(SvUV(value))); //Value refaddr
    SV *hval = newSVsv(value); //reference to store in the forward hash
    if(!SvROK(value)) {
        die("Value must be a reference!");
    }
    HE *vhash_ent; //Value's reverse entry in reverse table
    SV *vhash; //Value's lookup references
    
    int key_is_ref = SvROK(key);
    
    int iopts = STORE_OPT_O_CREAT;
    int i;
    
    dXSARGS;
    if( (items-3) % 2) {
        die("Odd number of extra arguments. Expected none or a hash of options (got %d)",
            items-3);
    }
    
    for(i = 3; i < items; i += 2) {
    #define _chkopt(option) \
        if(strcmp(STROPT_ ## option, SvPV_nolen(ST(i))) == 0 \
        && SvTRUE(ST(i+1))) { \
            iopts |= STORE_OPT_ ## option; \
            HR_DEBUG("Found option %s", STROPT_ ## option); \
            continue; \
        }
        _chkopt(STRONG_VALUE);
        _chkopt(STRONG_KEY);
        #undef _chkopt
    }
        
    kobj = ukey2ikey(self, key, &existing_ent, iopts);
    if(existing_ent) {
        HR_DEBUG("We're already stored");
        XSRETURN(0);
    }
        
    /*Not stored yet*/
    kstring = (key_is_ref) ? sv_2mortal(newSVuv(SvUV(key))) : sv_mortalcopy(key);
    get_hashes(table,
               HR_HKEY_LOOKUP_FORWARD, &flookup,
               HR_HKEY_LOOKUP_REVERSE, &rlookup,
               HR_HKEY_LOOKUP_NULL);
    /*Get value hashref*/
    vhash_ent = hv_fetch_ent(REF2HASH(rlookup), vstring, 1, 0);
    vhash = HeVAL(vhash_ent);
    if(!SvROK(vhash)) {
        SV *real_vhash = newRV_noinc((SV*)newHV());
        SvSetSV(vhash, real_vhash);
        SvREFCNT_dec(SvRV(real_vhash));
        HR_DEBUG("Inserted new value entry, refcount=%d", SvREFCNT(SvRV(real_vhash)));
    }
    
    /*PP: $self->reverse->{$vstring}->{$kstring} = $kobj*/
    hv_store_ent(REF2HASH(vhash), kstring, kobj, 0);    
    
    /*PP: $self->forward->{$kstring} = $value*/
    HR_DEBUG("Storing FLOOKUP{%s} (SV=%p) (RV=%p)", SvPV_nolen(kstring), hval, SvRV(hval));
    hv_store_ent(REF2HASH(flookup), kstring, hval, 0);

    
    /*PP: dred_add_ptr*/
    HR_PL_add_action_ptr(hval, rlookup);
    
    /*PP: $ko->link_value(); only valid for encapsulated keys*/
    if(key_is_ref) {
        HRXSK_encap_link_value(kobj, hval);
    }
    
    /*PP: if(!$options{StrongValue}) { weaken($self->forward->kstring)}*/
    if( (iopts & STORE_OPT_STRONG_VALUE) == 0) {
        HR_DEBUG("Weakening value");
        sv_rvweaken(hval);
    }
    
    XSRETURN(0);
}

SV *HRA_fetch_sk(SV *self, SV *key)
{
    SV *kobj = ukey2ikey(self, key, NULL, 0);
    SV *flookup;
    SV *ret = NULL;
    if(!kobj) {
        HR_DEBUG("Can't find key object!");
        return &PL_sv_undef;
    }
    key = SvROK(key) ? sv_2mortal(newSVuv(SvUV(key))) : key;
    get_hashes((HV*)SvRV(self),
               HR_HKEY_LOOKUP_FORWARD, &flookup,
               HR_HKEY_LOOKUP_NULL);
    
    HE *res = hv_fetch_ent(REF2HASH(flookup), key, 0, 0);
    if(res) {
        HR_DEBUG("Got result for %p", key);
        ret = newSVsv(HeVAL(res));
    } else {
        HR_DEBUG("Nothing for %p", key);
    }
    HR_DEBUG("Refcount for key: %d", SvREFCNT(SvRV(kobj)));
    return ret;
}