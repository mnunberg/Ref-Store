#ifndef HRPRIV_H_
#define HRPRIV_H_

#include "hreg.h"
#include <stdarg.h>

#define REF2HASH(ref) ((HV*)(SvRV(ref)))

#define HR_HKEY_RLOOKUP "reverse"
#define HR_HKEY_FLOOKUP "forward"
#define HR_HKEY_SLOOKUP "scalar_lookup"
#define HR_HKEY_KTYPES "keytypes"
#define HR_HKEY_ALOOKUP "attr_lookup"

#define HR_INLINE static inline

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

enum {
    HR_HKEY_LOOKUP_NULL     = 0,
    HR_HKEY_LOOKUP_SCALAR   = 1,
    HR_HKEY_LOOKUP_FORWARD  = 2,
    HR_HKEY_LOOKUP_REVERSE  = 3,
    HR_HKEY_LOOKUP_KT       = 4,
    HR_HKEY_LOOKUP_ATTR     = 5,
};

typedef char* HSpec[2];


enum {
    STORE_OPT_STRONG_KEY    = 1 << 0,
    STORE_OPT_STRONG_VALUE  = 1 << 1,
    STORE_OPT_O_CREAT       = 1 << 2
};
#define STORE_OPT_STRONG_ATTR (1 << 0)

#define PKG_BASE "Ref::Store::XS"

#define PKG_KEY_SCALAR  PKG_BASE "::Key"
#define PKG_KEY_ENCAP   PKG_BASE "::Key::Encapsulating"
#define PKG_ATTR_SCALAR PKG_BASE "::Attribute"
#define PKG_ATTR_ENCAP  PKG_BASE "::Attribute::Encapsulating"

#define STROPT_STRONG_KEY "StrongKey"
#define STROPT_STRONG_VALUE "StrongValue"
#define STROPT_STRONG_ATTR "StrongAttr"

/*This macro will convert string hash options into bitflags for the
 various store functions
*/

#define _chkopt(option_id, iter, optvar) \
    if(strcmp(STROPT_ ## option_id, SvPV_nolen(ST(iter))) == 0 \
    && SvTRUE(ST(iter+1))) { \
        optvar |= STORE_OPT_ ## option_id; \
        HR_DEBUG("Found option %s", STROPT_ ## option_id); \
        continue; \
    }

extern HSpec HR_LookupKeys[];

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