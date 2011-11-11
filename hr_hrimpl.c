#include "hreg.h"
#include <perl.h>


/*Hash::Registry::Key::new*/
void HR_impl_key_init(SV *keyobj, SV *forward_table, SV *scalar_lookup,
                      char *scalar_key)
{
    HR_Action actions[] = {
        {
            .key = (char*)SvRV(keyobj),
            .ktype = HR_KEY_TYPE_PTR,
            .hashref = forward_table,
        },
        {
            .key = scalar_key,
            .ktype = HR_KEY_TYPE_STR,
            .hashref = scalar_lookup,
        },
        { NULL, NULL, HR_KEY_TYPE_NULL, NULL }
    };
    HR_add_actions_real(keyobj, actions);
}

/*Hash::Registry::Value::value_init*/
void HR_impl_value_init(SV *vobj, SV *reverse)
{
    HR_Action actions[] = {
        {
            .key = (char*)SvRV(vobj),
            .ktype = HR_KEY_TYPE_PTR,
            .hashref = reverse
        },
        {
            NULL, NULL, HR_KEY_TYPE_NULL, NULL
        }
    };
    HR_add_actions_real(vobj, actions);
}

void HR_impl_value_init_a(SV* vobj, SV* attrhash)
{
    HR_Action actions[] = {
        {
            .key = (char*)SvRV(vobj),
            .ktype = HR_KEY_TYPE_PTR,
            .hashref = attrhash
        },
        {
            NULL, NULL, HR_KEY_TYPE_NULL, NULL
        }
    };
    HR_add_actions_real(vobj, actions);
}
