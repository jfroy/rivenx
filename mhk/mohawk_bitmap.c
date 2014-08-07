// Copyright 2005 Jean-Francois Roy. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be found in the LICENSE file.

#include "mhk/mohawk_bitmap.h"

#include <Accelerate/Accelerate.h>

#include "Base/RXBase.h"
#include "Base/RXBufferMacros.h"

static const size_t READ_BUFFER_SIZE = 0x1000;

typedef struct {
  void* buffer;
  size_t buffer_size;

  void* data;
  ssize_t data_size;

  int fd;
  off_t offset;
} MHK_io_buffer;

static void io_buffer_init(int fd, off_t offset, size_t max_size, MHK_io_buffer* io_buffer) {
  debug_assert(io_buffer);

  io_buffer->buffer = malloc(max_size);
  io_buffer->buffer_size = max_size;

  io_buffer->data = io_buffer->buffer;
  io_buffer->data_size = 0;

  io_buffer->fd = fd;
  io_buffer->offset = offset;
}

static void io_buffer_free(MHK_io_buffer* io_buffer) {
  debug_assert(io_buffer);
  free(io_buffer->buffer);
  memset(io_buffer, 0, sizeof(MHK_io_buffer));
}

static int io_buffer_read(MHK_io_buffer* io_buffer, const ssize_t requested, void* buffer, ssize_t* actual) {
  ssize_t local_actual = 0;

  // how many bytes can be read from the buffer, and how many bytes do we have left to supply
  ssize_t available_from_buffer = 0;
  ssize_t size_left = requested;

  // while we need to supply bytes
  while (size_left > 0) {
    // if the IO buffer is empty, attempt to fill it
    if (io_buffer->data_size == 0) {
      available_from_buffer = pread(io_buffer->fd, io_buffer->buffer, io_buffer->buffer_size, io_buffer->offset);
      if (available_from_buffer < 0) {
        return -1;
      } else if (available_from_buffer == 0) {
        return 0;
      }

      // update the IO buffer's state
      io_buffer->offset += available_from_buffer;
      io_buffer->data_size = available_from_buffer;
      io_buffer->data = io_buffer->buffer;
    }

    // supply some more bytes
    available_from_buffer = (size_left <= io_buffer->data_size) ? size_left : io_buffer->data_size;
    memcpy(buffer, io_buffer->data, available_from_buffer);

    // update the client's state
    buffer = BUFFER_OFFSET(buffer, available_from_buffer);
    local_actual += available_from_buffer;
    size_left -= available_from_buffer;

    // update the IO buffer's state
    io_buffer->data_size -= available_from_buffer;
    io_buffer->data = BUFFER_OFFSET(io_buffer->data, available_from_buffer);
  }

  if (actual) {
    *actual = local_actual;
  }

  return 0;
}

bool read_raw_bgr_pixels(int fd, off_t offset, MHK_BITMAP_header* header, void* bgra_buffer) {
  debug_assert(header);

  ssize_t image_size = header->bytes_per_row * header->height;

  // prepare a vImage_Buffer that will contain the file's RGB888 pixels
  vImage_Buffer file_buffer;
  file_buffer.rowBytes = header->bytes_per_row;
  file_buffer.width = header->width;
  file_buffer.height = header->height;
  file_buffer.data = malloc(image_size);

  // read the pixels
  if (pread(fd, file_buffer.data, image_size, offset) < image_size) {
    goto AbortReadBGRPixels;
  }

  // storage for the final BGRA image
  vImage_Buffer client_buffer;
  client_buffer.rowBytes = header->width * 4;
  client_buffer.width = header->width;
  client_buffer.height = header->height;
  client_buffer.data = bgra_buffer;

  // convert the image to BGRA
  vImage_Error verr = vImageConvert_RGB888toBGRA8888(&file_buffer, NULL, 0xff, &client_buffer, false, kvImageNoFlags);
  if (verr != kvImageNoError) {
    goto AbortReadBGRPixels;
  }

  // we're done
  return 0;

AbortReadBGRPixels:
  free(file_buffer.data);
  return -1;
}

bool read_raw_indexed_pixels(int fd, off_t offset, MHK_BITMAP_header* header, void* bgra_buffer) {
  // storage for the file color table
  Pixel_8 file_color_table_storage[256][3];

  // storage for the color table
  Pixel_F color_table_storage[256];

  // file color table
  vImage_Buffer fct_buffer;
  fct_buffer.rowBytes = 256 * 3;
  fct_buffer.width = 256;
  fct_buffer.height = 1;
  fct_buffer.data = file_color_table_storage;

  // storage for the indexed pixels
  vImage_Buffer file_buffer;
  file_buffer.rowBytes = header->bytes_per_row;
  file_buffer.width = header->width;
  file_buffer.height = header->height;
  file_buffer.data = malloc(file_buffer.rowBytes * file_buffer.height);

  // read the color table
  ssize_t bytes_read;
  bytes_read = pread(fd, fct_buffer.data, sizeof(file_color_table_storage), offset);
  if (bytes_read < (ssize_t)sizeof(file_color_table_storage)) {
    goto AbortReadIndexedPixels;
  }

  // color table
  vImage_Buffer ct_buffer;
  ct_buffer.rowBytes = 256 * 4;
  ct_buffer.width = 256;
  ct_buffer.height = 1;
  ct_buffer.data = color_table_storage;

  // create the BGRA color table
  vImage_Error verr = vImageConvert_RGB888toBGRA8888(&fct_buffer, NULL, 0xff, &ct_buffer, false, kvImageNoFlags);
  if (verr != kvImageNoError) {
    goto AbortReadIndexedPixels;
  }

  // advance the offset past the color table
  offset += bytes_read;

  // read the pixels
  bytes_read = pread(fd, file_buffer.data, file_buffer.rowBytes * file_buffer.height, offset);
  if (bytes_read < (ssize_t)(file_buffer.rowBytes * file_buffer.height)) {
    goto AbortReadIndexedPixels;
  }

  // storage for the final BGRA image
  vImage_Buffer client_buffer;
  client_buffer.rowBytes = header->width * 4;
  client_buffer.width = header->width;
  client_buffer.height = header->height;
  client_buffer.data = bgra_buffer;

  // do the entire color lookup operation in one sweet function call
  verr = vImageLookupTable_Planar8toPlanarF(&file_buffer, &client_buffer, color_table_storage, kvImageNoFlags);
  if (verr != kvImageNoError) {
    goto AbortReadIndexedPixels;
  }

  // we're done
  return 0;

AbortReadIndexedPixels:
  free(file_buffer.data);
  return -1;
}

bool read_compressed_indexed_pixels(int fd, off_t offset, MHK_BITMAP_header* header, void* bgra_buffer) {
  // storage for the file color table
  Pixel_8 file_color_table_storage[256][3];

  // storage for the color table
  Pixel_F color_table_storage[256];

  // file IO buffer
  MHK_io_buffer io_buffer;
  memset(&io_buffer, 0, sizeof(MHK_io_buffer));

  // file color table
  vImage_Buffer fct_buffer;
  fct_buffer.rowBytes = 256 * 3;
  fct_buffer.width = 256;
  fct_buffer.height = 1;
  fct_buffer.data = file_color_table_storage;

  // read the color table
  ssize_t bytes_read;
  bytes_read = pread(fd, fct_buffer.data, sizeof(file_color_table_storage), offset);
  if (bytes_read < (ssize_t)sizeof(file_color_table_storage)) {
    goto AbortReadCompressedIndexedPixels;
  }

  // color table
  vImage_Buffer ct_buffer;
  ct_buffer.rowBytes = 256 * 4;
  ct_buffer.width = 256;
  ct_buffer.height = 1;
  ct_buffer.data = color_table_storage;

  // create the BGRA color table
  vImage_Error verr = vImageConvert_RGB888toBGRA8888(&fct_buffer, NULL, 0xff, &ct_buffer, false, kvImageNoFlags);
  if (verr != kvImageNoError) {
    goto AbortReadCompressedIndexedPixels;
  }

  // advance the offset past the color table and skip 4 bytes
  offset += bytes_read + 4;

  // storage for the indexed pixels
  vImage_Buffer file_buffer;
  file_buffer.rowBytes = header->bytes_per_row;
  file_buffer.width = header->width;
  file_buffer.height = header->height;
  file_buffer.data = malloc(file_buffer.rowBytes * file_buffer.height);

  // decompressor state variables
  uint8_t instruction = 0;
  uint8_t operand = 0;
  uint32_t pixel_index = 0;
  uint32_t pixel_count = header->bytes_per_row * header->height;
  Pixel_8* file_pixels = file_buffer.data;
  int err;

  // init the io buffer
  io_buffer_init(fd, offset, READ_BUFFER_SIZE, &io_buffer);

  // decompress the indexed pixels
  while (pixel_index < pixel_count) {
    // read an instruction
    err = io_buffer_read(&io_buffer, 1, &instruction, NULL);
    if (err) {
      goto AbortReadCompressedIndexedPixels;
    }

    // instruction 0 indicates end of instruction stream
    if (instruction == 0) {
      break;
    }

    // separate the operand from the instruction
    operand = instruction & 0x3f;
    instruction &= 0xc0;

    // execute the instruction
    if (instruction == 0) {
      err = io_buffer_read(&io_buffer, operand * 2, file_pixels + pixel_index, &bytes_read);
      if (err) {
        goto AbortReadCompressedIndexedPixels;
      }
      pixel_index += bytes_read;
    } else if (instruction == 0x40) {
      Pixel_8 x[2] = {file_pixels[pixel_index - 2], file_pixels[pixel_index - 1]};
      uint8_t i = 0;
      for (; i < operand; i++) {
        file_pixels[pixel_index++] = x[0];
        file_pixels[pixel_index++] = x[1];
      }
    } else if (instruction == 0x80) {
      uint8_t i = 0;
      Pixel_8 x[4] = {file_pixels[pixel_index - 4],
                      file_pixels[pixel_index - 3],
                      file_pixels[pixel_index - 2],
                      file_pixels[pixel_index - 1]};
      for (; i < operand; i++) {
        file_pixels[pixel_index] = x[0];
        file_pixels[pixel_index + 1] = x[1];
        file_pixels[pixel_index + 2] = x[2];
        file_pixels[pixel_index + 3] = x[3];
        pixel_index += 4;
      }
    } else if (instruction == 0xc0) {
      uint8_t i = 0;
      uint8_t n = operand;
      for (; i < n; i++) {
        // read an instruction
        err = io_buffer_read(&io_buffer, 1, &instruction, NULL);
        if (err) {
          goto AbortReadCompressedIndexedPixels;
        }

        // separate the operand from the instruction
        operand = instruction & 0x0f;
        instruction &= 0xf0;

        // execute the instruction
        if (instruction == 0) {
          // repeat duplet at -operand offset, where operand is a duplet index
          uint16_t pixel_offset = 2 * operand;
          file_pixels[pixel_index] = file_pixels[pixel_index - pixel_offset];
          file_pixels[pixel_index + 1] = file_pixels[pixel_index - pixel_offset + 1];
        } else if (instruction == 0x10 && operand == 0) {
          // repeat last duplet then change second pixel to pixel from stream
          file_pixels[pixel_index] = file_pixels[pixel_index - 2];
          err = io_buffer_read(&io_buffer, 1, file_pixels + pixel_index + 1, NULL);
          if (err) {
            goto AbortReadCompressedIndexedPixels;
          }
        } else if (instruction == 0x10) {
          // output first pixel of last duplet then pixel at offset operand
          file_pixels[pixel_index] = file_pixels[pixel_index - 2];
          file_pixels[pixel_index + 1] = file_pixels[pixel_index - operand + 1];
        } else if (instruction == 0x20) {
          // repeat last duplet then add operand to second pixel
          file_pixels[pixel_index] = file_pixels[pixel_index - 2];
          file_pixels[pixel_index + 1] = file_pixels[pixel_index - 1] + operand;
        } else if (instruction == 0x30) {
          // repeat last duplet then subtract operand from second pixel
          file_pixels[pixel_index] = file_pixels[pixel_index - 2];
          file_pixels[pixel_index + 1] = file_pixels[pixel_index - 1] - operand;
        } else if (instruction == 0x40 && operand == 0) {
          // repeat last duplet then change first pixel to pixel from stream
          err = io_buffer_read(&io_buffer, 1, file_pixels + pixel_index, NULL);
          if (err) {
            goto AbortReadCompressedIndexedPixels;
          }
          file_pixels[pixel_index + 1] = file_pixels[pixel_index - 1];
        } else if (instruction == 0x40) {
          // output pixel at offset operand then second pixel of last duplet
          file_pixels[pixel_index] = file_pixels[pixel_index - operand];
          file_pixels[pixel_index + 1] = file_pixels[pixel_index - 1];
        } else if (instruction == 0x50 && operand == 0) {
          // output 2 pixels from stream
          err = io_buffer_read(&io_buffer, 2, file_pixels + pixel_index, NULL);
          if (err) {
            goto AbortReadCompressedIndexedPixels;
          }
        } else if (instruction == 0x50 && operand < 8) {
          // output pixel at offset operand then pixel from stream
          operand &= 0x07;
          file_pixels[pixel_index] = file_pixels[pixel_index - operand];
          err = io_buffer_read(&io_buffer, 1, file_pixels + pixel_index + 1, NULL);
          if (err) {
            goto AbortReadCompressedIndexedPixels;
          }
        } else if (instruction == 0x50) {
          // output pixel from stream then pixel at offset operand
          operand &= 0x07;
          err = io_buffer_read(&io_buffer, 1, file_pixels + pixel_index, NULL);
          if (err) {
            goto AbortReadCompressedIndexedPixels;
          }
          file_pixels[pixel_index + 1] = file_pixels[pixel_index - operand + 1];
        } else if (instruction == 0x60) {
          // output pixel from stream then second pixel of last duplet + operand
          err = io_buffer_read(&io_buffer, 1, file_pixels + pixel_index, NULL);
          if (err) {
            goto AbortReadCompressedIndexedPixels;
          }
          file_pixels[pixel_index + 1] = file_pixels[pixel_index - 1] + operand;
        } else if (instruction == 0x70) {
          // output pixel from stream then second pixel of last duplet - operand
          err = io_buffer_read(&io_buffer, 1, file_pixels + pixel_index, NULL);
          if (err) {
            goto AbortReadCompressedIndexedPixels;
          }
          file_pixels[pixel_index + 1] = file_pixels[pixel_index - 1] - operand;
        } else if (instruction == 0x80) {
          // repeat last duplet then add operand to first pixel
          file_pixels[pixel_index] = file_pixels[pixel_index - 2] + operand;
          file_pixels[pixel_index + 1] = file_pixels[pixel_index - 1];
        } else if (instruction == 0x90) {
          // output first pixel of last duplet + operand then pixel from stream
          file_pixels[pixel_index] = file_pixels[pixel_index - 2] + operand;
          err = io_buffer_read(&io_buffer, 1, file_pixels + pixel_index + 1, NULL);
          if (err) {
            goto AbortReadCompressedIndexedPixels;
          }
        } else if (instruction == 0xa0 && operand == 0) {
          // repeat last duplet then add next nibble to first pixel and next nibble to second pixel
          err = io_buffer_read(&io_buffer, 1, &operand, NULL);
          if (err) {
            goto AbortReadCompressedIndexedPixels;
          }
          file_pixels[pixel_index] = file_pixels[pixel_index - 2] + ((operand >> 4) & 0x0f);
          file_pixels[pixel_index + 1] = file_pixels[pixel_index - 1] + (operand & 0x0f);
        } else if (instruction == 0xa0) {
          // copy n bytes from large offset + extra optional pixel instruction
          uint8_t pixel_offset_low = 0;
          err = io_buffer_read(&io_buffer, 1, &pixel_offset_low, NULL);
          if (err) {
            goto AbortReadCompressedIndexedPixels;
          }

          // compute the final offset
          uint16_t pixel_offset = (uint16_t)((operand & 0x03) << 8);
          pixel_offset |= pixel_offset_low;

          // top 2 bits of operand determine the mode
          operand &= 0x0c;
          if (operand == 0x4) {
            // 3 bytes and extra
            file_pixels[pixel_index] = file_pixels[pixel_index - pixel_offset];
            file_pixels[pixel_index + 1] = file_pixels[pixel_index - pixel_offset + 1];
            file_pixels[pixel_index + 2] = file_pixels[pixel_index - pixel_offset + 2];

            err = io_buffer_read(&io_buffer, 1, file_pixels + pixel_index + 3, NULL);
            if (err) {
              goto AbortReadCompressedIndexedPixels;
            }

            pixel_index += 2;
          } else if (operand == 0x08) {
            // 4 bytes
            file_pixels[pixel_index] = file_pixels[pixel_index - pixel_offset];
            file_pixels[pixel_index + 1] = file_pixels[pixel_index - pixel_offset + 1];
            file_pixels[pixel_index + 2] = file_pixels[pixel_index - pixel_offset + 2];
            file_pixels[pixel_index + 3] = file_pixels[pixel_index - pixel_offset + 3];

            pixel_index += 2;
          } else {
            // 5 bytes and extra
            file_pixels[pixel_index] = file_pixels[pixel_index - pixel_offset];
            file_pixels[pixel_index + 1] = file_pixels[pixel_index - pixel_offset + 1];
            file_pixels[pixel_index + 2] = file_pixels[pixel_index - pixel_offset + 2];
            file_pixels[pixel_index + 3] = file_pixels[pixel_index - pixel_offset + 3];
            file_pixels[pixel_index + 4] = file_pixels[pixel_index - pixel_offset + 4];

            err = io_buffer_read(&io_buffer, 1, file_pixels + pixel_index + 5, NULL);
            if (err) {
              goto AbortReadCompressedIndexedPixels;
            }

            pixel_index += 4;
          }
        } else if (instruction == 0xb0 && operand == 0) {
          // repeat last duplet then add next nibble to first pixel then subtract next nibble from second pixel
          err = io_buffer_read(&io_buffer, 1, &operand, NULL);
          if (err) {
            goto AbortReadCompressedIndexedPixels;
          }
          file_pixels[pixel_index] = file_pixels[pixel_index - 2] + ((operand >> 4) & 0x0f);
          file_pixels[pixel_index + 1] = file_pixels[pixel_index - 1] - (operand & 0x0f);
        } else if (instruction == 0xb0) {
          // copy n bytes from large offset + extra optional pixel instruction
          uint8_t pixel_offset_low = 0;
          err = io_buffer_read(&io_buffer, 1, &pixel_offset_low, NULL);
          if (err) {
            goto AbortReadCompressedIndexedPixels;
          }

          // compute the final offset
          uint16_t pixel_offset = (uint16_t)((operand & 0x03) << 8);
          pixel_offset |= pixel_offset_low;

          // pixel counter
          uint8_t i_pixel = 0;
          uint8_t n_pixel = 0;

          // top 2 bits of operand determine the mode
          operand &= 0x0c;
          if (operand == 0x4) {
            // 6 bytes
            for (n_pixel = 6; i_pixel < n_pixel; i_pixel++) {
              file_pixels[pixel_index + i_pixel] = file_pixels[pixel_index - pixel_offset + i_pixel];
            }

            pixel_index += 4;
          } else if (operand == 0x08) {
            // 7 bytes and extra
            for (n_pixel = 7; i_pixel < n_pixel; i_pixel++) {
              file_pixels[pixel_index + i_pixel] = file_pixels[pixel_index - pixel_offset + i_pixel];
            }

            err = io_buffer_read(&io_buffer, 1, file_pixels + pixel_index + 7, NULL);
            if (err) {
              goto AbortReadCompressedIndexedPixels;
            }

            pixel_index += 6;
          } else {
            // 8 bytes
            for (n_pixel = 8; i_pixel < n_pixel; i_pixel++) {
              file_pixels[pixel_index + i_pixel] = file_pixels[pixel_index - pixel_offset + i_pixel];
            }

            pixel_index += 6;
          }
        } else if (instruction == 0xc0) {
          // repeat last duplet then subtract operand from first pixel
          file_pixels[pixel_index] = file_pixels[pixel_index - 2] - operand;
          file_pixels[pixel_index + 1] = file_pixels[pixel_index - 1];
        } else if (instruction == 0xd0) {
          // output first pixel of last duplet - operand then pixel from stream
          file_pixels[pixel_index] = file_pixels[pixel_index - 2] - operand;
          err = io_buffer_read(&io_buffer, 1, file_pixels + pixel_index + 1, NULL);
          if (err) {
            goto AbortReadCompressedIndexedPixels;
          }
        } else if (instruction == 0xe0 && operand == 0) {
          // repeat last duplet then subtract next nibble from first pixel then add next nibble to second pixel
          err = io_buffer_read(&io_buffer, 1, &operand, NULL);
          if (err) {
            goto AbortReadCompressedIndexedPixels;
          }
          file_pixels[pixel_index] = file_pixels[pixel_index - 2] - ((operand >> 4) & 0x0f);
          file_pixels[pixel_index + 1] = file_pixels[pixel_index - 1] + (operand & 0x0f);
        } else if (instruction == 0xe0) {
          // copy n bytes from large offset + extra optional pixel instruction
          uint8_t pixel_offset_low = 0;
          err = io_buffer_read(&io_buffer, 1, &pixel_offset_low, NULL);
          if (err) {
            goto AbortReadCompressedIndexedPixels;
          }

          // compute the final offset
          uint16_t pixel_offset = (uint16_t)((operand & 0x03) << 8);
          pixel_offset |= pixel_offset_low;

          // pixel counter
          uint8_t i_pixel = 0;
          uint8_t n_pixel = 0;

          // top 2 bits of operand determine the mode
          operand &= 0x0c;
          if (operand == 0x4) {
            // 9 bytes and extra
            for (n_pixel = 9; i_pixel < n_pixel; i_pixel++) {
              file_pixels[pixel_index + i_pixel] = file_pixels[pixel_index - pixel_offset + i_pixel];
            }

            err = io_buffer_read(&io_buffer, 1, file_pixels + pixel_index + 9, NULL);
            if (err) {
              goto AbortReadCompressedIndexedPixels;
            }

            pixel_index += 8;
          } else if (operand == 0x08) {
            // 10 bytes
            for (n_pixel = 10; i_pixel < n_pixel; i_pixel++) {
              file_pixels[pixel_index + i_pixel] = file_pixels[pixel_index - pixel_offset + i_pixel];
            }

            pixel_index += 8;
          } else if (operand == 0x0c) {
            // 11 bytes and extra
            for (n_pixel = 11; i_pixel < n_pixel; i_pixel++) {
              file_pixels[pixel_index + i_pixel] = file_pixels[pixel_index - pixel_offset + i_pixel];
            }

            err = io_buffer_read(&io_buffer, 1, file_pixels + pixel_index + 11, NULL);
            if (err) {
              goto AbortReadCompressedIndexedPixels;
            }

            pixel_index += 10;
          }
        } else if (instruction == 0xf0 && operand == 0) {
          // repeat last duplet then subtract next nibble from first pixel and next nibble from second pixel
          err = io_buffer_read(&io_buffer, 1, &operand, NULL);
          if (err) {
            goto AbortReadCompressedIndexedPixels;
          }
          file_pixels[pixel_index] = file_pixels[pixel_index - 2] - ((operand >> 4) & 0x0f);
          file_pixels[pixel_index + 1] = file_pixels[pixel_index - 1] - (operand & 0x0f);
        } else if (instruction == 0xf0 && operand < 0x0c) {
          // copy n bytes from large offset + extra optional pixel instruction
          uint8_t pixel_offset_low = 0;
          err = io_buffer_read(&io_buffer, 1, &pixel_offset_low, NULL);
          if (err) {
            goto AbortReadCompressedIndexedPixels;
          }

          // compute the final offset
          uint16_t pixel_offset = (uint16_t)((operand & 0x03) << 8);
          pixel_offset |= pixel_offset_low;

          // pixel counter
          uint8_t i_pixel = 0;
          uint8_t n_pixel = 0;

          // top 2 bits of operand determine the mode
          operand &= 0x0c;
          if (operand == 0x4) {
            // 12 bytes
            for (n_pixel = 12; i_pixel < n_pixel; i_pixel++) {
              file_pixels[pixel_index + i_pixel] = file_pixels[pixel_index - pixel_offset + i_pixel];
            }

            pixel_index += 10;
          } else if (operand == 0x08) {
            // 13 bytes and extra
            for (n_pixel = 13; i_pixel < n_pixel; i_pixel++) {
              file_pixels[pixel_index + i_pixel] = file_pixels[pixel_index - pixel_offset + i_pixel];
            }

            err = io_buffer_read(&io_buffer, 1, file_pixels + pixel_index + 13, NULL);
            if (err) {
              goto AbortReadCompressedIndexedPixels;
            }

            pixel_index += 12;
          }
        } else if (instruction == 0xf0 && operand >= 0x0c) {
          // fancy copy n bytes from large offset + extra optional pixel instruction
          uint16_t pixel_offset = 0;
          err = io_buffer_read(&io_buffer, 2, &pixel_offset, NULL);
          if (err) {
            goto AbortReadCompressedIndexedPixels;
          }

          // byte swap to big endian if needed
          pixel_offset = CFSwapInt16BigToHost(pixel_offset);

          // extract the top 6 bits of pixel_offset
          uint8_t n_pixel = (pixel_offset >> 10) + 3;

          // mask to keep only the low 2 bits of the second byte
          pixel_offset &= 0x03ff;

          // copy some pixels around
          uint8_t i_pixel = 0;
          for (; i_pixel < n_pixel; i_pixel++) {
            file_pixels[pixel_index + i_pixel] = file_pixels[pixel_index - pixel_offset + i_pixel];
          }

          // check if we need to read an extra pixel from stream
          if ((n_pixel & 0x01)) {
            err = io_buffer_read(&io_buffer, 1, file_pixels + pixel_index + i_pixel, NULL);
            if (err) {
              goto AbortReadCompressedIndexedPixels;
            }
            pixel_index++;
          }

          // negate n_pixel by 2 to offset the += 2 we do for every instruction
          pixel_index += n_pixel - 2;
        }

        // every instruction ouputs at least 2 pixels
        pixel_index += 2;
      }
    }
  }

  // we do not need the IO buffer anymore
  io_buffer_free(&io_buffer);

  // storage for the final BGRA image
  vImage_Buffer client_buffer;
  client_buffer.rowBytes = header->width * 4;
  client_buffer.width = header->width;
  client_buffer.height = header->height;
  client_buffer.data = bgra_buffer;

  // do the entire color lookup operation in one sweet function call
  verr = vImageLookupTable_Planar8toPlanarF(&file_buffer, &client_buffer, color_table_storage, kvImageNoFlags);
  if (verr != kvImageNoError) {
    goto AbortReadCompressedIndexedPixels;
  }

  // we're done
  return 0;

AbortReadCompressedIndexedPixels:
  io_buffer_free(&io_buffer);
  free(file_buffer.data);
  return -1;
}
