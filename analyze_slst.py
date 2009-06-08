#!/usr/bin/env python

import objc
import os
import struct
import sys

from Foundation import NSData

def parse_slst(slst_string):
    count_fmt = '>H'
    count = struct.unpack_from(count_fmt, slst_string)
    offset = struct.calcsize(count_fmt)
    
    slsts = []
    for i in xrange(count[0]):
        header_fmt = '>HH'
        header = struct.unpack_from(header_fmt, slst_string, offset)
        offset += struct.calcsize(header_fmt)
    
        sound_ids_fmt = '>' + ('H' * header[1])
        sound_ids = struct.unpack_from(sound_ids_fmt, slst_string, offset)
        offset += struct.calcsize(sound_ids_fmt)
    
        header2_fmt = '>HHHHH'
        header2 = struct.unpack_from(header2_fmt, slst_string, offset)
        offset += struct.calcsize(header2_fmt)
    
        volumes_fmt = '>' + ('H' * header[1])
        volumes = struct.unpack_from(volumes_fmt, slst_string, offset)
        offset += struct.calcsize(volumes_fmt)
    
        pans_fmt = '>' + ('h' * header[1])
        pans = struct.unpack_from(pans_fmt, slst_string, offset)
        offset += struct.calcsize(pans_fmt)
    
        u2s_fmt = '>' + ('H' * header[1])
        u2s = struct.unpack_from(u2s_fmt, slst_string, offset)
        offset += struct.calcsize(u2s_fmt)
    
        slsts.append({
            'index': header[0],
            'fade_flags': header2[0],
            'loop': header2[1],
            'volume': header2[2],
            'u0': header2[3],
            'u1': header2[4],
            'sounds': [{'ID': sound_ids[i], 'volume': volumes[i], 'pan': pans[i]} for i in xrange(header[1])],
        })
    return slsts

if __name__ == '__main__':
    objc.loadBundle("MHKKit", globals(), bundle_path=objc.pathForFramework('build/Debug/MHKKit.framework'))
    
    dvd_edition = '/Users/bahamut/Library/Application Support/Riven X/DVD_EDITION/Data'
    archives = ['a_Data.MHK', 'b_Data.MHK', 'g_Data.MHK', 'j_Data1.MHK', 'j_Data2.MHK', 'o_Data.MHK', 'p_Data.MHK', 'r_Data.MHK', 't_Data1.MHK', 't_Data2.MHK']
    
    min_pan = 1000.0
    min_pan_slst = None
    max_pan = -1000.0
    max_pan_slst = None
    
    for name in archives:
        print "processing %s" % name
        processed_slsts = 0
        
        archive = MHKArchive.alloc().initWithPath_error_(os.path.join(dvd_edition, name), None)
        if archive is None:
            continue
        
        slst_resources = archive.valueForKey_("SLST")
        for slst in slst_resources:
            processed_slsts += 1
            
            slst_data = archive.dataWithResourceType_ID_('SLST', slst['ID'])
            if not slst_data or slst_data.length() == 0:
                continue

            #slst_data = NSData.dataWithData_(slst_data)
            slsts = parse_slst(str(slst_data))
            for slst_dict in slsts:
                for sound in slst_dict['sounds']:
                    pan = sound['pan']
                    if pan < min_pan:
                        min_pan = pan
                        min_pan_slst = (name, slst, slst_dict)
                    if pan > max_pan:
                        max_pan = pan
                        max_pan_slst = (name, slst, slst_dict)
        print "    analyzed %d SLST resource" % processed_slsts
    
    print "max pan: %f from %s\nmin pan: %f from %s" % (max_pan, max_pan_slst, min_pan, min_pan_slst)
