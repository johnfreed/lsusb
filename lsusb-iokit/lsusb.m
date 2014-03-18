//
//  lsusb.m
//  lsusb-iokit
//
//  Created by John Freed on 15 March 2014.
//
// Based on http://stackoverflow.com/questions/7567872/how-to-create-a-program-to-list-all-the-usb-devices-in-a-mac
// and http://lists.apple.com/archives/usb/2007/Nov/msg00038.html
// and work by J.L. Honora

#include <CoreFoundation/CoreFoundation.h>
#include <CoreFoundation/CFString.h>
#include <IOKit/IOKitLib.h>
#include <IOKit/usb/IOUSBLib.h>
#include <IOKit/usb/USB.h>
#include <IOKit/IOCFPlugIn.h>
#include <Foundation/Foundation.h>

void process_usb_device(io_service_t * device);
static bool getVidAndPid(io_service_t * device, int *vid, int *pid);
char * getVendorName(io_service_t * device);
char * getSerialNumber(io_service_t * device);
int getDeviceAddress(io_service_t * device);
char * getVendorNameFromVendorID(NSString * intValueAsString);

int main(int argc, const char *argv[])
{
    printf("Starting\n");
    CFMutableDictionaryRef matchingDict;
    io_iterator_t iter;
    kern_return_t kr;
    io_service_t device;
    
    /* set up a matching dictionary for the class */
    matchingDict = IOServiceMatching(kIOUSBDeviceClassName);
    if (matchingDict == NULL) {
        return -1; // fail
    }
    
    /* Now we have a dictionary, get an iterator.*/
    kr = IOServiceGetMatchingServices(kIOMasterPortDefault, matchingDict, &iter);
    if (kr != KERN_SUCCESS) {
        return -1;
    }
    
    /* iterate */
    while ((device = IOIteratorNext(iter))) {
        /* do something with device, eg. check properties */
        process_usb_device(&device);
        /* And free the reference taken before continuing to the next item */
        IOObjectRelease(device);
    }
    
    
    /* Done, release the iterator */
    IOObjectRelease(iter);
    printf("Done\n");
    return 0;
}

typedef struct USBDevice_t {
    char deviceName[200];
    int vid, pid;
    char * manufacturer;
    char * serial;
    int address;
} USBDevice;

void process_usb_device(io_service_t * device) {
    USBDevice d;
    IORegistryEntryGetName(*device, d.deviceName);
    if(!strcmp(d.deviceName,"HubDevice")) {
        strcpy(d.deviceName, "Hub");
    }
    getVidAndPid(device, &(d.vid), &(d.pid));
    d.manufacturer = getVendorName(device);
    d.serial = getSerialNumber(device);
    d.address = getDeviceAddress(device);
    printf("Device %d: ID %04x:%04x (%s) %s", d.address, d.vid, d.pid, d.manufacturer, d.deviceName);
    if(d.serial != NULL) {
        printf(" Serial: %s", d.serial);
    }
    printf("\n");
}

static bool getVidAndPid(io_service_t * device, int *vid, int *pid) {
	bool success;
	CFNumberRef cfVendorId = (CFNumberRef)IORegistryEntryCreateCFProperty(*device, CFSTR("idVendor"), kCFAllocatorDefault, 0);
	if (cfVendorId && (CFGetTypeID(cfVendorId) == CFNumberGetTypeID())) {
		success = CFNumberGetValue(cfVendorId, kCFNumberSInt32Type, vid);
		CFRelease(cfVendorId);
		if (!success) {
            return (success);
        }
    }
	CFNumberRef cfProductId = (CFNumberRef) IORegistryEntryCreateCFProperty(*device, CFSTR("idProduct"), kCFAllocatorDefault, 0);
	if (cfProductId && (CFGetTypeID(cfProductId) == CFNumberGetTypeID())) {
		success = CFNumberGetValue(cfProductId, kCFNumberSInt32Type, pid);
		CFRelease(cfProductId);
	}
	return (success);
}

char * getVendorNameFromVendorID(NSString * intValueAsString) {
    static NSMutableDictionary * gVendorNamesDictionary = nil;
    NSString *VendorName;
    if (gVendorNamesDictionary == nil) {
        gVendorNamesDictionary = [[NSMutableDictionary dictionary] init];
        NSString *vendorListString = [NSString stringWithContentsOfFile:[[NSBundle mainBundle] pathForResource:@"USBVendors" ofType:@"txt"] encoding:NSUTF8StringEncoding error:NULL];
        
        if (vendorListString == nil) {
            NSLog(@"USB Prober: Error reading USBVendors.txt from the Resources directory");
        } else {
            NSArray *vendorsAndIDs = [vendorListString componentsSeparatedByString:@"\n"];
            if (vendorsAndIDs == nil) {
                NSLog(@"USB Prober: Error parsing USBVendors.txt");
            } else {
                NSEnumerator *enumerator = [vendorsAndIDs objectEnumerator];
                NSString *vendorIDCombo;
                NSArray *aVendor;
                while ((vendorIDCombo = [enumerator nextObject])) {
                    aVendor = [vendorIDCombo componentsSeparatedByString:@"|"];
                    if (aVendor == nil || [aVendor count] < 2) {
                        continue;
                    }
                    [gVendorNamesDictionary setObject:[aVendor objectAtIndex:1] forKey:[aVendor objectAtIndex:0]];
                }
            }
        }
    }
    
   VendorName = [gVendorNamesDictionary objectForKey:intValueAsString];
    
//NSLog(@"%@",VendorName);
    return (char *) CFStringGetCStringPtr((CFStringRef)VendorName, kCFStringEncodingMacRoman);
    
}

char * getVendorName(io_service_t * device) {
    if(!device) return NULL;
    
    USBDevice d;
    CFStringRef vendorName;
    NSMutableString  *nsVendorName = [NSMutableString string];
    getVidAndPid(device, &(d.vid), &(d.pid));
    if (d.vid) {
        //look up VID in table, and return name if found, otherwise fall through to device's vendor name field
       return getVendorNameFromVendorID([NSString stringWithFormat:@"%d", d.vid ]);
    } else {
        return NULL;
    }
    vendorName = IORegistryEntryCreateCFProperty(*device, CFSTR("USB Vendor Name"), kCFAllocatorDefault, 0);
    return (char *) CFStringGetCStringPtr(vendorName, kCFStringEncodingMacRoman);
}


char * getSerialNumber(io_service_t * device) {
    if(!device) return NULL;
    CFStringRef serialNumber = IORegistryEntryCreateCFProperty(*device, CFSTR("USB Serial Number"), kCFAllocatorDefault, 0);
    if(serialNumber == NULL)
        return NULL;
    return (char *) CFStringGetCStringPtr(serialNumber, kCFStringEncodingMacRoman);
}

int getDeviceAddress(io_service_t * device) {
    int address = 0;
    CFNumberRef	cfDeviceAddress = (CFNumberRef)IORegistryEntryCreateCFProperty(*device, CFSTR("USB Address"), kCFAllocatorDefault, 0);
	if (cfDeviceAddress && (CFGetTypeID(cfDeviceAddress) == CFNumberGetTypeID()))	{
		CFNumberGetValue(cfDeviceAddress, kCFNumberSInt32Type, &address);
		CFRelease(cfDeviceAddress);
    }
    return address;
}
