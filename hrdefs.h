#ifndef HRDEFS_H_
#define HRDEFS_H_

/*(Ordered) magic cookies for parent table fields, for get_hashes() */
enum {
	HR_HKEY_LOOKUP_NULL 	= 0,
	HR_HKEY_LOOKUP_SCALAR	= 1,
	HR_HKEY_LOOKUP_FORWARD	= 2,
	HR_HKEY_LOOKUP_REVERSE	= 3,
	HR_HKEY_LOOKUP_KT		= 4,
	HR_HKEY_LOOKUP_ATTR		= 5
};


/*When using hash-based parents, these are the field-key mapping*/
#define HR_HKEY_RLOOKUP "reverse"
#define HR_HKEY_FLOOKUP "forward"
#define HR_HKEY_SLOOKUP "scalar_lookup"
#define HR_HKEY_KTYPES "keytypes"
#define HR_HKEY_ALOOKUP "attr_lookup"


/*Possible options passed to ->store_*() */
#define HR_STROPT_STRONG_KEY 	"StrongKey"
#define HR_STROPT_STRONG_VALUE	"StrongValue"
#define HR_STROPT_STRONG_ATTR	"StrongAttr"

#define HR_PKG_BASE "Ref::Store::XS"

#define HR_PKG_KEY_SCALAR 	"Ref::Store::XS::Key"
#define HR_PKG_KEY_ENCAP	"Ref::Store::XS::Key::Encapsulating"
#define HR_PKG_ATTR_SCALAR	"Ref::Store::XS::Attribute"
#define HR_PKG_ATTR_ENCAP	"Ref::Store::XS::Attribute::Encapsulating"

#endif /*HRDEFS_H_*/