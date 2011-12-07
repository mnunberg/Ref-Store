#include "hreg.h"
#include "hrdefs.h"
#include "hrpriv.h"
#include "hr_duputil.h"

#include <string.h>

HSpec HR_LookupKeys[] = {
    {HR_HKEY_SLOOKUP, (char*)sizeof(HR_HKEY_SLOOKUP)-1},
    {HR_HKEY_FLOOKUP, (char*)sizeof(HR_HKEY_FLOOKUP)-1},
    {HR_HKEY_RLOOKUP, (char*)sizeof(HR_HKEY_RLOOKUP)-1},
    {HR_HKEY_KTYPES, (char*)sizeof(HR_HKEY_KTYPES)-1},
    {HR_HKEY_ALOOKUP, (char*)sizeof(HR_HKEY_ALOOKUP)-1}
};

typedef char hrk_simple;

typedef struct {
    SV* obj_ptr;
    SV* table;
    void *obj_paddr;
} hrk_encap;

static inline HV*
get_v_hashref(hrk_encap *ke, SV* value);

#ifdef HR_MAKE_PARENT_RV
#error HR_MAKE_PARENT_RV is no longer supported
#else
#define ketbl_from_ke(ke) (HV*)(ke->table);
#endif


#define keptr_from_sv(svp) \
    ((hrk_encap*)(SvPVX(svp)))

#define ksimple_from_sv(svp) \
    ((hrk_simple*)(SvPVX(svp)))

#define ksimple_strkey(ksp) \
    ((char*)(((char*)ksp)+1))

/*We find our information about ourselves here, and place it inside our
 private pointer table*/

static void k_encap_cleanup(SV *ksv, SV *_)
{
    /*Find our forward entry from the stringified object pointer*/
    hrk_encap *ke = keptr_from_sv(ksv);
    HV *table = ketbl_from_ke(ke);
    if(!table) {
        warn("Is table being destroyed?");
        goto GT_CLEANUP;
    }
    
    SV *scalar_lookup, *forward, *reverse;
    
    //SvREFCNT(table)++;
    get_hashes(table,
               HR_HKEY_LOOKUP_REVERSE, &reverse,
               HR_HKEY_LOOKUP_FORWARD, &forward,
               HR_HKEY_LOOKUP_SCALAR, &scalar_lookup,
               HR_HKEY_LOOKUP_NULL
    );
    //SvREFCNT(table)--;
    
    
    if(!(scalar_lookup && forward && reverse)) {
        die("Uhh...: (S=%p, F=%p, R=%p, REFCOUNT=%d", scalar_lookup, forward, reverse,
            SvREFCNT(table));
    }
    
    if( (!ke->obj_ptr) || (!SvROK(ke->obj_ptr))) {
        HR_DEBUG("Object has been deleted.");
    } else {
        HR_DEBUG("Freeing magic triggers on encapsulated object");
        HR_PL_del_action_container(ke->obj_ptr, scalar_lookup);
        HR_PL_del_action_container(ke->obj_ptr, forward);
        HR_DEBUG("Done!");
    }
    
    /*Perform the deletion manually*/
    mk_ptr_string(obj_s, ke->obj_paddr);
    HR_DEBUG("obj_s=%s", obj_s);
    
    SV **stored = NULL;
    stored = hv_fetch( REF2HASH(forward), obj_s, strlen(obj_s), 0);
    if(!stored) {
        HR_DEBUG("Can't find stored value in forward table");
        goto GT_CLEANUP;
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
            HR_PL_del_action_container(*stored, reverse);
        }
    } else {
        HR_DEBUG("Can't find anything!");
    }
    
    hv_delete( REF2HASH(scalar_lookup), obj_s, strlen(obj_s), G_DISCARD);
    hv_delete( REF2HASH(forward), obj_s, strlen(obj_s), G_DISCARD );
    
    GT_CLEANUP:
    SvREFCNT_dec(ke->obj_ptr);
    ke->obj_ptr = NULL;
    HR_DEBUG("On cleanup, we are refcount=%d", SvREFCNT(ksv));
    HR_DEBUG("Returning...");
}

void HRXSK_encap_link_value(SV *self, SV *value)
{
    HR_DEBUG("LINK VALUE!");
    hrk_encap *ke = keptr_from_sv(SvRV(self));
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
            .key   = (char*)SvRV(ke->obj_ptr),
#ifdef HR_MAKE_PARENT_RV
            .flags = HR_FLAG_HASHREF_WEAKEN,
#endif
            .hashref = hashref_ptr,
        },
        HR_ACTION_LIST_TERMINATOR
    };
    HR_add_actions_real(ke->obj_ptr, vdel_actions);
    
    SvREFCNT_dec(hashref_ptr);
    HR_DEBUG("Hashref_ptr refcount=%d, hash refcount=%d",
             SvREFCNT(hashref_ptr), SvREFCNT(v_hashref));
}

void HRXSK_encap_weaken(SV *ksv_ref)
{
    hrk_encap *ke = keptr_from_sv(SvRV(ksv_ref));
    HR_DEBUG("Weakening encapsulated object reference");
    sv_rvweaken(ke->obj_ptr);
}

UV HRXSK_encap_kstring(SV* ksv_ref)
{
    hrk_encap *ke = keptr_from_sv(SvRV(ksv_ref));
    return (UV)SvRV(ke->obj_ptr);
}

SV *HRXSK_encap_getencap(SV *ksv_ref)
{
    hrk_encap *ke = keptr_from_sv(SvRV(ksv_ref));
    die("Unsupported!");
    return newSVsv(ke->obj_ptr);
}

SV* HRXSK_encap_new(char *package, SV* object, SV *table, SV* forward, SV* scalar_lookup)
{
    
    HR_DEBUG("Encap key");
    SV *ksv = mk_blessed_blob(package, sizeof(hrk_encap));
    if(!ksv) {
        die("couldn't create hrk_encap!");
        return NULL;
    }
    hrk_encap *keptr = keptr_from_sv(SvRV(ksv));
    keptr->obj_ptr = newRV_inc(SvRV(object));
    keptr->obj_paddr = (char*)SvRV(object);
    
#ifdef HR_MAKE_PARENT_RV
    keptr->table = newSVsv(table);
#else
    keptr->table = SvRV(table);
#endif
    HR_DEBUG("New blessed class (%s)", package);
    
    mk_ptr_string(key_s, SvRV(object));
    HR_DEBUG("Have string key %s", key_s);
    HR_DEBUG("Scalar lookup: %p", scalar_lookup);
    
    SV *self_hval = newSVsv(ksv);
    sv_rvweaken(self_hval);
    hv_store( REF2HASH(scalar_lookup), key_s, strlen(key_s), self_hval, 0);
    
    HR_Action encap_actions[] = {
        HR_DREF_FLDS_ptr_from_hv(SvRV(object), scalar_lookup),
        HR_ACTION_LIST_TERMINATOR
    };
    
    HR_Action key_actions[] = {
        HR_DREF_FLDS_arg_for_cfunc(SvRV(ksv), &k_encap_cleanup),
        HR_ACTION_LIST_TERMINATOR
    };
    
    HR_add_actions_real(object, encap_actions);
    HR_add_actions_real(ksv, key_actions);
    HR_DEBUG("Returning key %p", SvRV(ksv));
    return ksv;
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
        return (HV*)SvRV(*privhash);
    } else {
        HR_DEBUG("Can't get privhash from hv_fetch");
        return NULL;
    }
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
    SV *ksv = mk_blessed_blob(package, bloblen);
    if(!ksv) {
        die("Couldn't create package!");
        return NULL;
    }    
    /* blob: [key data] [key string] */
    char *blob = SvPVX(SvRV(ksv));
    char *key_offset = blob + sizeof(newkey);
    
    /*Initialize the blob*/
    Zero(blob, 1, hrk_simple);
    /*Segfaults on the next line if SvPV_nolen is used instead of SvPVX*/
    Copy(key, key_offset, keylen, char);
    
    SV **scalar_entry = hv_store(REF2HASH(scalar_lookup),
                                 key, keylen-1,
                                 newSVsv(ksv), 0);
    if(!scalar_entry) {
        die("Couldn't add entry!");
    }
    sv_rvweaken(*scalar_entry);
    
    HR_Action actions[] = {
        HR_DREF_FLDS_Estr_from_hv(key_offset, scalar_lookup),
        HR_DREF_FLDS_Estr_from_hv(key_offset, forward),
        HR_ACTION_LIST_TERMINATOR
    };
    
    HR_add_actions_real(ksv, actions);
    return ksv;
}

char * HRXSK_kstring(SV *obj)
{
    char *blob = SvPVX(SvRV(obj));
    char *ret = strkey_from_simple(blob);
    HR_DEBUG("Requested key=%s", ret);
    return ret;
}

////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////
/// Ref::Store API implementation (keys)                                 ///
////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////
static inline SV* ukey2ikey(
    SV* self,
    SV* key,
    SV** existing, /*PP: Argument to $options{O_EXCL}: $expected*/
    int options)
{
    SV *slookup = NULL, *flookup = NULL;
    SV *kobj = NULL;
    
    get_hashes(REF2HASH(self),
               HR_HKEY_LOOKUP_SCALAR, &slookup,
               HR_HKEY_LOOKUP_NULL);
    
    int key_is_ref = SvROK(key);
    SV *our_key = (key_is_ref) ? newSVuv(SvUV(key)) : key;    
    HR_DEBUG("Using key %s", SvPV_nolen(our_key));
    
    /*PP: my $o = $self->scalar_lookup->{$ustr}; */
    HE *stored_key = hv_fetch_ent(REF2HASH(slookup), our_key, 0, 0);
    
    if(stored_key && (kobj = HeVAL(stored_key))) {
        /*PP: if ($expected != $existing) */
        if(existing && SvROK(kobj) && SvRV(kobj) != SvRV(*existing)) {
             die("Requested new key storage for value %p, but key is already "
                 "linked to %p", SvRV(*existing), SvRV(kobj));
        } else {
            if(existing) *existing = kobj;
            goto GT_RET;
        }
    }
    
    if(existing) *existing = NULL; /*No previous key*/
    /*The previous block always returns*/
    
    if( (options & STORE_OPT_O_CREAT) == 0 ) {
        goto GT_RET;
    }
    
    /*else { */
    get_hashes(REF2HASH(self),
        HR_HKEY_LOOKUP_FORWARD, &flookup,
        HR_HKEY_LOOKUP_NULL);
    
    /*
    PP: sub Ref::Store::XS::new_key($self,$ukey) {
        if(ref $key) {
            HRXSK_new(PKG_KEY_SCALAR, $key, $self->forward, $self->scalar_lookup);
        } else {
            HRXSK_encap_new(PKG_KEY_ENCAP, $key, $self->forward, $self->scalar_lookup);
        }
    }
    */
    if(key_is_ref) {
        /*This function will do (among other things) the equivalent of:
            newRV_inc(SvRV(our_key));
        */
        kobj =  HRXSK_encap_new(HR_PKG_KEY_ENCAP,
                    key, self, flookup, slookup);
        /*PP: if(!$options{StrongKey}) { $o->weaken_encapsulated() }*/
        if( (options & STORE_OPT_STRONG_KEY) == 0) {
            HRXSK_encap_weaken(kobj);
        }
    } else {
        kobj = HRXSK_new(HR_PKG_KEY_SCALAR,
                SvPV_nolen(our_key), flookup, slookup);
        /*XS Simple key's weaken_encapsulated is nop*/
    }
    
    GT_RET:
    if(key_is_ref && our_key) {
        SvREFCNT_dec(our_key);
    }
    return kobj;
}

void HRA_store_sk(SV *self, SV *key, SV *value, ...)
{
    SV *flookup = NULL,  *rlookup = NULL; //Lookup tables
    SV *kobj = NULL, *kstring = NULL; // Key object and string
    SV *vstring = newSVuv(SvUV(value)); //Value refaddr
    SV *hval = newSVsv(value); //reference to store in the forward hash
    SV *existing_ent = value; /* SV** to send/receive options for O_CREAT/O_EXCL*/
    
    if(!SvROK(value)) {
        die("Value must be a reference!");
    }

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
        _chkopt(STRONG_VALUE, i, iopts);
        _chkopt(STRONG_KEY, i, iopts);
    }
    
    kobj = ukey2ikey(self, key, &existing_ent, iopts);
    if(existing_ent) {
        HR_DEBUG("We're already stored");
        XSRETURN(0);
    }
        
    /*Not stored yet*/
    kstring = (key_is_ref) ? newSVuv(SvUV(key)) : key;    
    get_hashes(REF2HASH(self),
               HR_HKEY_LOOKUP_FORWARD, &flookup,
               HR_HKEY_LOOKUP_REVERSE, &rlookup,
               HR_HKEY_LOOKUP_NULL);
    /*Get value hashref*/
    vhash = get_vhash_from_rlookup(rlookup, vstring, 1);
    assert(vhash);
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
    
    GT_CLEANUP:
    if(key_is_ref) {
        SvREFCNT_dec(kstring);
    }
    SvREFCNT_dec(vstring);
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
    int key_is_ref = SvROK(key);
    key = (key_is_ref) ? newSVuv(SvUV(key)) : key;
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
    if(key_is_ref) {
        SvREFCNT_dec(key);
    }
    return ret;
}

////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////
/// iThread Duplication Handlers                                             ///
////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////
void HRA_ithread_store_lookup_info(SV *self, HV *ptr_map)
{
    hr_dup_store_old_lookups(ptr_map, (HV*)SvRV(self));
}

void HRXSK_encap_ithread_predup(SV *self, SV *table, HV *ptr_map, SV *value)
{
    hrk_encap *ke = keptr_from_sv(SvRV(self));   
    HR_Dup_Kinfo *ki = hr_dup_store_kinfo(ptr_map, HR_DUPKEY_KENCAP, ke->obj_paddr, 0);
    
    if(SvWEAKREF(ke->obj_ptr)) {
        ki->flags = HRK_DUP_WEAK_ENCAP;
    } else {
        ki->flags = 0;
    }
    
    HV *vhash = get_v_hashref(ke, value);
    ki->vhash = vhash;
    
    hr_dup_store_rv(ptr_map, ke->obj_ptr);
}

void HRXSK_encap_ithread_postdup(SV *newself, SV *newtable, HV *ptr_map, UV old_table)
{
    hrk_encap *ke = keptr_from_sv(SvRV(newself));
    
    HR_Dup_OldLookups *old_lookups = hr_dup_get_old_lookups(ptr_map, ke->table);
    HR_Dup_Kinfo *ki = hr_dup_get_kinfo(ptr_map, HR_DUPKEY_KENCAP, ke->obj_paddr);
    
    HR_DEBUG("Old vhash was %p, old obj_paddr was %p", ki->vhash, ke->obj_paddr);
    
    SV *new_encap = hr_dup_newsv_for_oldsv(ptr_map, ke->obj_paddr, 0);
    SV *new_vhash = hr_dup_newsv_for_oldsv(ptr_map, ki->vhash, 0);
    
    SV *new_slookup;
    get_hashes(REF2HASH(newtable),
               HR_HKEY_LOOKUP_SCALAR, &new_slookup,
               HR_HKEY_LOOKUP_NULL);
        
    HR_Action key_actions[] = {
        HR_DREF_FLDS_arg_for_cfunc(SvRV(newself), &k_encap_cleanup),
        HR_ACTION_LIST_TERMINATOR
    };
    
    HR_Action encap_actions[] = {
        HR_DREF_FLDS_ptr_from_hv(SvRV(new_encap), new_slookup),
        HR_DREF_FLDS_ptr_from_hv(SvRV(new_encap), new_vhash),
        HR_ACTION_LIST_TERMINATOR
    };
    
    HR_add_actions_real(newself, key_actions);
    HR_add_actions_real(new_encap, encap_actions);
    
    ke->obj_paddr = SvRV(new_encap);
    ke->obj_ptr = newSVsv(new_encap);
    if(ki->flags & HRK_DUP_WEAK_ENCAP) {
        sv_rvweaken(ke->obj_ptr);
    }
    ke->table = SvRV(newtable);
    HR_DEBUG("Reassigned %p", SvRV(newtable));
}

void HRXSK_ithread_postdup(SV *newself, SV *newtable, HV *ptr_map, UV old_table)
{
    hrk_simple *ksp = ksimple_from_sv(SvRV(newself));
    char *key = ksimple_strkey(ksp);
    
    SV *slookup, *flookup;
    get_hashes(REF2HASH(newtable),
               HR_HKEY_LOOKUP_SCALAR, &slookup,
               HR_HKEY_LOOKUP_FORWARD, &flookup,
               HR_HKEY_LOOKUP_NULL);
    
    HR_Action key_actions[] = {
        HR_DREF_FLDS_Estr_from_hv(key, slookup),
        HR_DREF_FLDS_Estr_from_hv(key, flookup),
        HR_ACTION_LIST_TERMINATOR
    };
    HR_add_actions_real(newself, key_actions);
}