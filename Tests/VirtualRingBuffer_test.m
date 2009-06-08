/*
 *  VirtualRingBuffer_test.m
 *  rivenx
 *
 *  Created by Jean-Francois Roy on 17/03/2006.
 *  Copyright 2006 MacStorm. All rights reserved.
 *
 */

#import <Foundation/Foundation.h>
#import "VirtualRingBuffer.h"

int test_normal_buffer() {
    VirtualRingBuffer* buffer;
    
    const uint32_t data = 0xDECAFBAD;
    uint32_t read_data = 0x0;
    
    void* read_pointer;
    void* write_pointer;
    
    UInt32 available_read;
    UInt32 available_write;
    
    UInt32 old_available_read;
    UInt32 old_available_write;
    
    UInt32 copy_count_for_fill;
    UInt32 copy_counter;
    UInt32 copy_byte_count;
    
    // test normal ring buffer
    RXLog(@"-- Testing a normal ring buffer --");
    
    buffer = [[VirtualRingBuffer alloc] initWithLength:1];
    if (!buffer) {
        RXLog(@"Could not allocate and init the buffer!");
        return 1;
    }
    
    RXLog(@"%@", buffer);
    
    // buffer should be empty
    if (![buffer isEmpty]) {
        RXLog(@"Buffer wasn't empty after initialization.");
        return 1;
    }
    
    // buffer should have 0 bytes available for reading
    available_read = [buffer lengthAvailableToReadReturningPointer:&read_pointer];
    if (available_read != 0) {
        RXLog(@"Buffer reported bytes available for reading before after initialization.");
        return 1;
    }
    
    // buffer should have one VM page of free space
    available_write = [buffer lengthAvailableToWriteReturningPointer:&write_pointer];
    if(available_write != 0x1000) {
        RXLog(@"Buffer reported an incorrect number of bytes available for writing after initialization.");
    }
    
    // buffer should still have 0 bytes available for reading
    available_read = [buffer lengthAvailableToReadReturningPointer:&read_pointer];
    if (available_read != 0) {
        RXLog(@"Buffer reported bytes available for reading before first write was committed.");
        return 1;
    }
    
    // write some bytes and commit
    memcpy(write_pointer, &data, sizeof(data));
    [buffer didWriteLength:sizeof(data)];
    
    // buffer should not be empty
    if ([buffer isEmpty]) {
        RXLog(@"Buffer reported empty after first write was committed.");
        return 1;
    }
    
    // buffer should have sizeof(data) bytes available for reading
    available_read = [buffer lengthAvailableToReadReturningPointer:&read_pointer];
    if (available_read != sizeof(data)) {
        RXLog(@"Buffer reported an incorrect number of bytes available for reading after first write was committed.");
        return 1;
    }
    
    // buffer should have sizeof(data) less bytes available for writing
    old_available_write = available_write;
    available_write = [buffer lengthAvailableToWriteReturningPointer:&write_pointer];
    if(available_write != old_available_write - sizeof(data)) {
        RXLog(@"Buffer reported an incorrect number of bytes available for writing after first write was committed.");
        return 1;
    }
    
    // read some bytes
    memcpy(&read_data, read_pointer, sizeof(data));
    [buffer didReadLength:sizeof(data)];
    
    // check for data integrity
    if (read_data != data) {
        RXLog(@"Incorrect data read back from the buffer.");
        return 1;
    }
    
    // buffer should be empty again
    if (![buffer isEmpty]) {
        RXLog(@"Buffer reported not empty after first read was committed.");
        return 1;
    }
    
    // buffers should have sizeof(read_data) less bytes available for reading
    old_available_read = available_read;
    available_read = [buffer lengthAvailableToReadReturningPointer:&read_pointer];
    if(available_read != old_available_read - sizeof(data)) {
        RXLog(@"Buffer reported an incorrect number of bytes available for reading after first read was committed.");
        return 1;
    }
    
    // buffer should have sizeof(data) more bytes available for writing
    old_available_write = available_write;
    available_write = [buffer lengthAvailableToWriteReturningPointer:&write_pointer];
    if(available_write != old_available_write + sizeof(data)) {
        RXLog(@"Buffer reported an incorrect number of bytes available for writing after first read was committed.");
        return 1;
    }
    
    // write some bytes and commit
    memcpy(write_pointer, &data, sizeof(data));
    [buffer didWriteLength:sizeof(data)];
    
    // test empty
    [buffer empty];
    
    // buffer should be empty again
    if (![buffer isEmpty]) {
        RXLog(@"Buffer reported not empty after explicit empty.");
        return 1;
    }
    
    // let's fill the buffer
    available_write = [buffer lengthAvailableToWriteReturningPointer:&write_pointer];
    if(available_write != 0x1000) {
        RXLog(@"Buffer reported an incorrect number of bytes available for writing after empty.");
    }
    
    copy_count_for_fill = 0x1000 / sizeof(data);
    copy_byte_count = 0;
    
    // write!
    for(copy_counter = 0; copy_counter < copy_count_for_fill; copy_counter++) {
        memcpy(write_pointer, &data, sizeof(data));
        write_pointer += sizeof(data);
        copy_byte_count += sizeof(data);
    }
    
    // remainder
    copy_counter = available_write % sizeof(data);
    if (copy_counter > 0) {
        memcpy(write_pointer, &data, copy_counter);
        copy_byte_count += copy_counter;
    }
    
    // sanity check...
    if (copy_byte_count != 0x1000) {
        RXLog(@"Did not copy nominal buffer length bytes!");
        return 1;
    }
    
    // commit write
    [buffer didWriteLength:copy_byte_count];
    
    // buffer should not have any space left for writing
    available_write = [buffer lengthAvailableToWriteReturningPointer:&write_pointer];
    if(available_write != 0) {
        RXLog(@"Buffer reported bytes available for writing after buffer fill was committed.");
        return 1;
    }
    
    // buffer should have full buffer size available for reading
    available_read = [buffer lengthAvailableToReadReturningPointer:&read_pointer];
    if (available_read != 0x1000) {
        RXLog(@"Buffer reported an incorrect number of bytes available for reading after buffer fill was committed.");
        return 1;
    }
    
    /* 
        let's test wrap around
        method: 
                - read half the fill bytes (puts the read pointer halfway through the nominal length)
                - write half the nominal length (puts the write pointer at the read pointer)
                - read the nominal length of bytes
                - test for data coherency
    */
    
    // read half the fill bytes
    [buffer didReadLength:0x800];
    
    // buffer should have 0x800 bytes available for reading and writing
    available_read = [buffer lengthAvailableToReadReturningPointer:&read_pointer];
    if (available_read != 0x800) {
        RXLog(@"Buffer reported an incorrect number of bytes available for reading after reading half the buffer fill bytes. 0x%x bytes", available_read);
        return 1;
    }
    
    // buffer should have one VM page of free space
    available_write = [buffer lengthAvailableToWriteReturningPointer:&write_pointer];
    if(available_write != 0x800) {
        RXLog(@"Buffer reported an incorrect number of bytes available for writing after reading half the buffer fill bytes.");
    }
    
    // write half the nominal length
    copy_count_for_fill = 0x800 / sizeof(data);
    copy_byte_count = 0;
    
    // write!
    for(copy_counter = 0; copy_counter < copy_count_for_fill; copy_counter++) {
        memcpy(write_pointer, &data, sizeof(data));
        write_pointer += sizeof(data);
        copy_byte_count += sizeof(data);
    }
    
    // remainder
    copy_counter = available_write % sizeof(data);
    if (copy_counter > 0) {
        memcpy(write_pointer, &data, copy_counter);
        copy_byte_count += copy_counter;
    }
    
    // sanity check...
    if (copy_byte_count != 0x800) {
        RXLog(@"Did not copy half the nominal buffer length bytes!");
        return 1;
    }
    
    // commit write
    [buffer didWriteLength:copy_byte_count];
    
    // buffer should have nominal length bytes available
    available_read = [buffer lengthAvailableToReadReturningPointer:&read_pointer];
    if (available_read != 0x1000) {
        RXLog(@"Buffer reported an incorrect number of bytes available for reading after wrap around write was committed.");
        return 1;
    }
    
    // sample first value and check that it's sane
    memcpy(&read_data, read_pointer, sizeof(data));
    if (read_data != data) {
        RXLog(@"Incorrect data read back from the buffer after wrap around write.");
        return 1;
    }
    
    // commit read
    [buffer didReadLength:0x1000];
    
    // buffer should be empty
    if (![buffer isEmpty]) {
        RXLog(@"Buffer reported not empty after reading all wrap around bytes.");
        return 1;
    }
    
    // test successful
    [buffer release];
    RXLog(@"-- Normal ring buffer test passed --\n");
    return 0;
}

int main (int argc, char * const argv[]) {
    NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];
    int result = 0;
    
    result = test_normal_buffer();
    if (result != 0) return result;
    
    [pool release];
    return result;
}