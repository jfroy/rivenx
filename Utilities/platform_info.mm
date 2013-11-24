//
//  platform_info.cpp
//  rivenx
//
//  Copyright (c) 2012 MacStorm. All rights reserved.
//

#include "platform_info.h"

#include <sys/types.h>
#include <sys/sysctl.h>

#include <IOKit/IOKitLib.h>
#include <IOKit/network/IOEthernetInterface.h>
#include <IOKit/network/IONetworkInterface.h>
#include <IOKit/network/IOEthernetController.h>

#include <CoreFoundation/CFData.h>
#include <CoreServices/CoreServices.h>
#include <SystemConfiguration/SystemConfiguration.h>

// Returns an iterator containing the primary (built-in) Ethernet interface. The caller is responsible for
// releasing the iterator after the caller is done with it.
static kern_return_t new_ethernet_interfaces_iter(io_iterator_t* iterator)
{
  // Ethernet interfaces are instances of class kIOEthernetInterfaceClass.
  // IOServiceMatching is a convenience function to create a dictionary with the key kIOProviderClassKey and
  // the specified value.
  // Note that another option here would be: matchingDict = IOBSDMatching("en0");
  CFMutableDictionaryRef match_dictionary = IOServiceMatching(kIOEthernetInterfaceClass);
  if (match_dictionary == NULL)
    return KERN_FAILURE;

  // Each IONetworkInterface object has a Boolean property with the key kIOPrimaryInterface. Only the
  // primary (built-in) interface has this property set to TRUE.

  // IOServiceGetMatchingServices uses the default matching criteria defined by IOService. This considers
  // only the following properties plus any family-specific matching in this order of precedence
  // (see IOService::passiveMatch):
  //
  // kIOProviderClassKey (IOServiceMatching)
  // kIONameMatchKey (IOServiceNameMatching)
  // kIOPropertyMatchKey
  // kIOPathMatchKey
  // kIOMatchedServiceCountKey
  // family-specific matching
  // kIOBSDNameKey (IOBSDNameMatching)
  // kIOLocationMatchKey

  // The IONetworkingFamily does not define any family-specific matching. This means that in
  // order to have IOServiceGetMatchingServices consider the kIOPrimaryInterface property, we must
  // add that property to a separate dictionary and then add that to our matching dictionary
  // specifying kIOPropertyMatchKey.

  CFMutableDictionaryRef property_match_dictionary =
      CFDictionaryCreateMutable(kCFAllocatorDefault, 0, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
  if (property_match_dictionary == NULL) {
    CFRelease(match_dictionary);
    return KERN_FAILURE;
  }

  // Set the value in the dictionary of the property with the given key, or add the key
  // to the dictionary if it doesn't exist. This call retains the value object passed in.
  CFDictionarySetValue(property_match_dictionary, CFSTR(kIOPrimaryInterface), kCFBooleanTrue);

  // Now add the dictionary containing the matching value for kIOPrimaryInterface to our main
  // matching dictionary. This call will retain propertyMatchDict, so we can release our reference
  // on propertyMatchDict after adding it to matchingDict.
  CFDictionarySetValue(match_dictionary, CFSTR(kIOPropertyMatchKey), property_match_dictionary);
  CFRelease(property_match_dictionary);

  // IOServiceGetMatchingServices retains the returned iterator, so release the iterator when we're done with it.
  // IOServiceGetMatchingServices also consumes a reference on the matching dictionary so we don't need to release
  // the dictionary explicitly.
  return IOServiceGetMatchingServices(kIOMasterPortDefault, match_dictionary, iterator);
}

// Given an iterator across a set of Ethernet interfaces, return the MAC address of the last one.
// If no interfaces are found the MAC address is set to an empty string.
static CFDataRef copy_mac_address(io_iterator_t iterator)
{
  CFDataRef mac_address_data = NULL;

  // IOIteratorNext retains the returned object, so release it when we're done with it.
  io_object_t interface_service;
  while ((interface_service = IOIteratorNext(iterator))) {
    // IONetworkControllers can't be found directly by the IOServiceGetMatchingServices call,
    // since they are hardware nubs and do not participate in driver matching. In other words,
    // registerService() is never called on them. So we've found the IONetworkInterface and will
    // get its parent controller by asking for it specifically.

    // IORegistryEntryGetParentEntry retains the returned object, so release it when we're done with it.
    io_object_t controller_service;
    kern_return_t kerr = IORegistryEntryGetParentEntry(interface_service, kIOServicePlane, &controller_service);
    if (kerr == KERN_SUCCESS) {
      // Retrieve the MAC address property from the I/O Registry in the form of a CFData
      mac_address_data = (CFDataRef)IORegistryEntryCreateCFProperty(controller_service, CFSTR(kIOMACAddress), kCFAllocatorDefault, 0);
      if (mac_address_data && CFDataGetLength(mac_address_data) < kIOEthernetAddressSize) {
        CFRelease(mac_address_data);
        mac_address_data = NULL;
      }

      // Done with the parent Ethernet controller object so we release it.
      IOObjectRelease(controller_service);
    }

    // Done with the Ethernet interface object so we release it.
    IOObjectRelease(interface_service);

    if (mac_address_data)
      break;
  }

  return mac_address_data;
}

NSString* copy_principal_mac_address(void)
{
  io_iterator_t interface_iterator;
  kern_return_t kerr = new_ethernet_interfaces_iter(&interface_iterator);
  if (kerr != KERN_SUCCESS)
    return nil;

  CFDataRef mac_address_data = copy_mac_address(interface_iterator);
  IOObjectRelease(interface_iterator);

  if (mac_address_data == NULL)
    return nil;

  uint8_t const* mac_data_ptr = CFDataGetBytePtr(mac_address_data);
  NSString* mac_address = [[NSString alloc]
      initWithFormat:@"%02x:%02x:%02x:%02x:%02x:%02x", mac_data_ptr[0], mac_data_ptr[1], mac_data_ptr[2], mac_data_ptr[3], mac_data_ptr[4], mac_data_ptr[5]];

  CFRelease(mac_address_data);
  return mac_address;
}

NSString* copy_computer_name(void)
{
  NSString* name = NSMakeCollectable((NSString*)SCDynamicStoreCopyComputerName(NULL, NULL));
  if (name == nil) {
    char buf[1024];
    if (gethostname(buf, sizeof(buf)) == 0)
      name = [[NSString alloc] initWithCString:buf encoding:NSUTF8StringEncoding];
  }
  return name;
}

NSString* copy_system_version(void)
{
  NSDictionary* system_version_plist = [[NSDictionary alloc] initWithContentsOfFile:@"/System/Library/CoreServices/SystemVersion.plist"];
  NSString* version = [[system_version_plist objectForKey:@"ProductVersion"] retain];
  [system_version_plist release];
  return version;
}

NSString* copy_system_build(void)
{
  NSDictionary* system_version_plist = [[NSDictionary alloc] initWithContentsOfFile:@"/System/Library/CoreServices/SystemVersion.plist"];
  NSString* build = [[system_version_plist objectForKey:@"ProductBuildVersion"] retain];
  [system_version_plist release];
  return build;
}

NSString* copy_product_type(void)
{
  int sysctl_name[2] = {CTL_HW, HW_MODEL};
  size_t sysctl_size;
  int r = sysctl(sysctl_name, 2, NULL, &sysctl_size, NULL, 0);
  if (r == -1 || sysctl_size == 0ul)
    return nil;

  void* sysctl_data = malloc(sysctl_size);
  if (sysctl_data == NULL)
    return nil;

  NSString* product_type = nil;

  r = sysctl(sysctl_name, 2, sysctl_data, &sysctl_size, NULL, 0);
  if (r == 0)
    product_type = [[NSString alloc] initWithCString:(const char*)sysctl_data encoding:NSASCIIStringEncoding];

  free(sysctl_data);
  return product_type;
}

NSString* copy_hardware_uuid(void)
{
  NSString* uuid = nil;

  CFUUIDBytes uuidBytes;
  struct timespec timeout = {0, 0};
  int getuuidErr = gethostuuid((unsigned char*)&uuidBytes, &timeout);
  if (getuuidErr != -1) {
    CFUUIDRef uuidRef = CFUUIDCreateFromUUIDBytes(kCFAllocatorSystemDefault, uuidBytes);
    if (uuidRef != NULL) {
      uuid = (NSString*)NSMakeCollectable(CFUUIDCreateString(kCFAllocatorDefault, uuidRef));
      CFRelease(uuidRef);
    }
  }

  return uuid;
}
