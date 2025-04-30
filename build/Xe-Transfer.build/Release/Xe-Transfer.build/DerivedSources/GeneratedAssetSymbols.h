#import <Foundation/Foundation.h>

#if __has_attribute(swift_private)
#define AC_SWIFT_PRIVATE __attribute__((swift_private))
#else
#define AC_SWIFT_PRIVATE
#endif

/// The "AppLogo" asset catalog image resource.
static NSString * const ACImageNameAppLogo AC_SWIFT_PRIVATE = @"AppLogo";

/// The "DestinationIcon" asset catalog image resource.
static NSString * const ACImageNameDestinationIcon AC_SWIFT_PRIVATE = @"DestinationIcon";

/// The "DestinationIconHover" asset catalog image resource.
static NSString * const ACImageNameDestinationIconHover AC_SWIFT_PRIVATE = @"DestinationIconHover";

/// The "SourceIcon" asset catalog image resource.
static NSString * const ACImageNameSourceIcon AC_SWIFT_PRIVATE = @"SourceIcon";

/// The "SourceIconHover" asset catalog image resource.
static NSString * const ACImageNameSourceIconHover AC_SWIFT_PRIVATE = @"SourceIconHover";

#undef AC_SWIFT_PRIVATE
