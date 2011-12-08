#ifndef HRPRIV_H_
#define HRPRIV_H_

#include "hreg.h"
#include "hrdefs.h"

#include <stdarg.h>

#define REF2HASH(ref) ((HV*)(SvRV(ref)))

#define RV_Newtmp(vname, referrent) \
    vname = newRV_noinc((referrent));

#define RV_Freetmp(rv); \
    SvRV_set(rv, NULL); \
    SvROK_off(rv); \
    SvREFCNT_dec(rv);




enum {
    VHASH_NO_CREATE = 0,
    VHASH_NO_DREF   = 1,
    VHASH_INIT_FULL = 2,
};

typedef char* HSpec[2];


enum {
    STORE_OPT_STRONG_KEY    = 1 << 0,
    STORE_OPT_STRONG_VALUE  = 1 << 1,
    STORE_OPT_O_CREAT       = 1 << 2
};
#define STORE_OPT_STRONG_ATTR (1 << 0)

/*This macro will convert string hash options into bitflags for the
 various store functions
*/

#define _chkopt(option_id, iter, optvar) \
    if(strcmp(HR_STROPT_ ## option_id, SvPV_nolen(ST(iter))) == 0 \
    && SvTRUE(ST(iter+1))) { \
        optvar |= STORE_OPT_ ## option_id; \
        HR_DEBUG("Found option %s", HR_STROPT_ ## option_id); \
        continue; \
    }

extern HSpec HR_LookupKeys[];

#define FAKE_REFCOUNT (1 << 16)
HR_INLINE U32
refcnt_ka_begin(SV *sv)
{
    U32 ret = SvREFCNT(sv);
    SvREFCNT(sv) = FAKE_REFCOUNT;
    return ret;
}

HR_INLINE void
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


HR_INLINE void
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
        
        HSpec *kspec = (HSpec*)HR_LookupKeys[ltype-1];
        char *hkey = (*kspec)[0];
        int klen = (int)((*kspec)[1]);
        SV **result = hv_fetch(table, hkey, klen, 0);
        
        if(!result) {
            *hashptr = NULL;
        } else {
            *hashptr = *result;
        }
    }
    va_end(ap);
}

#define new_hashval_ref(vsv, referrent) \
    SvUPGRADE(vsv, SVt_RV); \
    SvRV_set(vsv, referrent); \
    SvROK_on(vsv);

HR_INLINE SV*
get_vhash_from_rlookup(SV *rlookup, SV *vaddr, int create)
{
    HE* h_ent = hv_fetch_ent(REF2HASH(rlookup), vaddr, create, 0);
    SV *href;
    if(h_ent && (href = HeVAL(h_ent)) && SvROK(href)) {
        return href;
    }
    if(!create) {
        return NULL;
    }
    
    /*Create*/
    HV *referrent = newHV();
    new_hashval_ref(href, (SV*)referrent);
    
    if(create == VHASH_INIT_FULL) {
        HR_DEBUG("Adding DREF for HV=%p", SvRV(rlookup));
        SV *vref = NULL;
        RV_Newtmp(vref, ((SV*)(SvUV(vaddr))) );
        HR_Action rlookup_delete[] = {
            HR_DREF_FLDS_ptr_from_hv(SvRV(vref), rlookup ),
            HR_ACTION_LIST_TERMINATOR
        };
        HR_add_actions_real(vref, rlookup_delete);
        RV_Freetmp(vref);
    }
    
    return href;
}

HR_INLINE SV*
mk_blessed_blob(char *pkg, int size)
{
    HR_DEBUG("New blob requested with size=%d", size);
    SV *referrant = newSV(size);
    HR_DEBUG("Allocated block=%p", SvPVX(referrant));
    HV *stash = gv_stashpv(pkg, 0);
    if(!stash) {
        die("Can't get stash for %pkg");
        SvREFCNT_dec(referrant);
        return NULL;
    }
    SV *self = newRV_noinc(referrant);
    sv_bless(self, stash);
    return self;
}


#endif /* HRPRIV_H_ */