//
//  platform_info.h
//  rivenx
//
//  Copyright (c) 2012 MacStorm. All rights reserved.
//

#pragma once

#include <Foundation/NSString.h>

__BEGIN_DECLS

extern NSString* copy_hardware_uuid(void);
extern NSString* copy_product_type(void);
extern NSString* copy_system_build(void);
extern NSString* copy_system_version(void);
extern NSString* copy_computer_name(void);
extern NSString* copy_principal_mac_address(void);

__END_DECLS
