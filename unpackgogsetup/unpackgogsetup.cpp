// Copyright 2014 Jean-Francois Roy. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be found in the LICENSE file.

#undef NDEBUG
#include <cassert>

#include <atomic>
#include <codecvt>
#include <iostream>
#include <locale>
#include <memory>
#include <string>
#include <thread>
#include <utility>
#include <vector>

#include <unistd.h>
#include <fcntl.h>
#include <errno.h>
#include <sys/stat.h>

#include <CommonCrypto/CommonDigest.h>

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdocumentation"
#include <lzma.h>
#pragma clang diagnostic pop
#include <zlib.h>

enum class CompressionMethod { None = 0, Zip, Bzip, LZMA, LZMA2 };

enum class ChecksumMethod {
  None = 0,
  MD5,
  SHA1,
};

template <typename Data, size_t UNICODE_STRINGS, size_t ASCII_STRINGS>
struct TSetupStruct {
  static const size_t N_UNICODE_STRINGS = UNICODE_STRINGS;
  static const size_t N_ASCII_STRINGS = ASCII_STRINGS;

  std::vector<std::string> strings;
  Data data;
};

namespace stored {

struct MD5Sum {
  uint8_t data[16];
} __attribute__((packed));

struct SHA1Sum {
  uint8_t data[20];
} __attribute__((packed));

struct SetupVersionData {
  uint8_t data[10];
} __attribute__((packed));

struct BlockInnerHeader {
  uint32_t data_size;
  uint8_t compressed;
} __attribute__((packed));

struct BlockHeader {
  uint32_t inner_header_crc32;
  BlockInnerHeader inner_header;
} __attribute__((packed));

struct Chunk {
  uint32_t data_crc32;
  uint8_t data[0x1000];
} __attribute__((packed));

struct Lzma1Header {
  uint8_t properties;
  uint32_t dictionary_size;
} __attribute__((packed));

struct Lzma2Header {
  uint8_t properties;
} __attribute__((packed));

struct File {
  static const size_t FILENAME_STRING_INDEX = 1;
};

struct FileLocation {
  enum Flags {
    VersionInfoValid = 1 << 0,
    VersionInfoNotValid = 1 << 1,
    TimestampInUTC = 1 << 2,
    IsUninstallExe = 1 << 3,
    CallInstructionOptimized = 1 << 4,
    Touch = 1 << 5,
    ChunkEncrypted = 1 << 6,
    ChunkCompressed = 1 << 7,
    SolidBreak = 1 << 8
  };
};

struct v523 {
  struct SetupHeader {
    uint8_t lead_bytes[32];
    uint32_t language_count;
    uint32_t custom_message_count;
    uint32_t permission_count;
    uint32_t type_count;
    uint32_t component_count;
    uint32_t task_count;
    uint32_t dir_count;
    uint32_t file_count;
    uint32_t file_location_count;
    uint32_t icon_count;
    uint32_t ini_count;
    uint32_t registry_count;
    uint32_t install_delete_count;
    uint32_t uninstall_delete_count;
    uint32_t run_count;
    uint32_t uninstall_run_count;
    SetupVersionData min_version;
    SetupVersionData only_below_version;
    uint32_t back_color;
    uint32_t back_color2;
    uint32_t wizard_image_back_color;
    MD5Sum password_hash;
    uint8_t password_salt[8];
    uint64_t extra_disk_space_required;
    uint32_t slices_per_disk;
    uint8_t uninstall_log_mode;
    uint8_t dir_exists_warning;
    uint8_t priviledges_required;
    uint8_t show_language_dialog;
    uint8_t language_detection_method;
    uint8_t compression_method;
    uint8_t architectures_allowed;
    uint8_t architectures_install_in_64_bit_mode;
    uint32_t signed_uninstaller_orig_size;
    uint32_t signed_uninstaller_header_checksum;
    uint8_t options[6];
  } __attribute__((packed));

  struct File {
    SetupVersionData min_version;
    SetupVersionData only_below_version;
    uint32_t file_location_index;
    uint32_t attributes;
    uint64_t external_size;
    uint16_t permission_index;
    uint32_t options;
    uint8_t file_type;
  } __attribute__((packed));

  struct FileLocation {
    uint32_t first_slice;
    uint32_t last_slice;
    uint32_t stored_offset;
    uint64_t chunk_suboffset;
    uint64_t original_size;
    uint64_t stored_size;
    MD5Sum checksum;
    uint64_t timestamp;
    uint64_t file_version;
    uint16_t flags;
  } __attribute__((packed));
};

struct v550 {
  struct SetupHeader {
    uint32_t language_count;
    uint32_t custom_message_count;
    uint32_t permission_count;
    uint32_t type_count;
    uint32_t component_count;
    uint32_t task_count;
    uint32_t dir_count;
    uint32_t file_count;
    uint32_t file_location_count;
    uint32_t icon_count;
    uint32_t ini_count;
    uint32_t registry_count;
    uint32_t install_delete_count;
    uint32_t uninstall_delete_count;
    uint32_t run_count;
    uint32_t uninstall_run_count;
    SetupVersionData min_version;
    SetupVersionData only_below_version;
    uint32_t back_color;
    uint32_t back_color2;
    uint32_t wizard_image_back_color;
    SHA1Sum password_hash;
    uint8_t password_salt[8];
    uint64_t extra_disk_space_required;
    uint32_t slices_per_disk;
    uint8_t uninstall_log_mode;
    uint8_t dir_exists_warning;
    uint8_t priviledges_required;
    uint8_t show_language_dialog;
    uint8_t language_detection_method;
    uint8_t compression_method;
    uint8_t architectures_allowed;
    uint8_t architectures_install_in_64_bit_mode;
    uint8_t disable_dir_page;
    uint8_t disable_program_group_page;
    uint64_t uninstall_display_size;
    uint8_t options[6];
  } __attribute__((packed));

  struct File {
    SetupVersionData min_version;
    SetupVersionData only_below_version;
    uint32_t file_location_index;
    uint32_t attributes;
    uint64_t external_size;
    uint16_t permission_index;
    uint32_t options;
    uint8_t file_type;
  } __attribute__((packed));

  struct FileLocation {
    uint32_t first_slice;
    uint32_t last_slice;
    uint32_t stored_offset;
    uint64_t chunk_suboffset;
    uint64_t original_size;
    uint64_t stored_size;
    SHA1Sum checksum;
    uint64_t timestamp;
    uint64_t file_version;
    uint16_t flags;
  } __attribute__((packed));
};

static uint32_t const FILE_DATA_MAGIC = 0x1A626C7A;

}  // namespace stored

struct v523 {
  using stored = stored::v523;

  typedef TSetupStruct<stored::SetupHeader, 0, 29> SetupHeader;
  typedef TSetupStruct<uint8_t[25], 0, 10> Language;
  typedef TSetupStruct<uint8_t[4], 0, 2> CustomMessage;
  typedef TSetupStruct<uint8_t[0], 0, 1> Permission;
  typedef TSetupStruct<uint8_t[30], 0, 4> Type;
  typedef TSetupStruct<uint8_t[42], 0, 5> Component;
  typedef TSetupStruct<uint8_t[26], 0, 6> Task;
  typedef TSetupStruct<uint8_t[27], 0, 7> Dir;
  typedef TSetupStruct<stored::File, 0, 9> File;
  typedef TSetupStruct<stored::FileLocation, 0, 0> FileLocation;

  constexpr static char const* const SETUP_DATA_BANNER = "Inno Setup Setup Data (5.2.3)";
  static off_t const SETUP_DATA_BANNER_OFFSET = 0x69C42BC3;
  static size_t const SETUP_DATA_BANNER_SIZE = 64ul;
  static off_t const FILE_DATA_OFFSET = 0x164C00;
  static ChecksumMethod const CHECKSUM_METHOD = ChecksumMethod::MD5;
};

struct v550 {
  using stored = stored::v550;

  typedef TSetupStruct<stored::SetupHeader, 27, 4> SetupHeader;
  typedef TSetupStruct<uint8_t[21], 6, 4> Language;
  typedef TSetupStruct<uint8_t[4], 2, 0> CustomMessage;
  typedef TSetupStruct<uint8_t[0], 0, 1> Permission;
  typedef TSetupStruct<uint8_t[30], 4, 0> Type;
  typedef TSetupStruct<uint8_t[42], 5, 0> Component;
  typedef TSetupStruct<uint8_t[26], 6, 0> Task;
  typedef TSetupStruct<uint8_t[27], 7, 0> Dir;
  typedef TSetupStruct<stored::File, 10, 0> File;
  typedef TSetupStruct<stored::FileLocation, 0, 0> FileLocation;

  constexpr static char const* const SETUP_DATA_BANNER = "Inno Setup Setup Data (5.5.0) (u)";
  static off_t const SETUP_DATA_BANNER_OFFSET = 0x6C023668;
  static size_t const SETUP_DATA_BANNER_SIZE = 64ul;
  static off_t const FILE_DATA_OFFSET = 0x2CE00;
  static ChecksumMethod const CHECKSUM_METHOD = ChecksumMethod::SHA1;
};

#pragma mark -

struct File {
  struct Checksum {
    Checksum() = default;
    Checksum(stored::MD5Sum& md5) { memcpy(md5_.data, md5.data, sizeof(md5.data)); }
    Checksum(stored::SHA1Sum& sha1) { memcpy(sha1_.data, sha1.data, sizeof(sha1.data)); }

    union {
      stored::MD5Sum md5_;
      stored::SHA1Sum sha1_;
    };
  };

  std::string filename;
  uint64_t original_size = UINT64_MAX;
  uint64_t stored_size = UINT64_MAX;
  uint32_t stored_offset = UINT32_MAX;
  Checksum checksum;
};

#pragma mark -

class BlockBuffer {
 public:
  BlockBuffer() : BlockBuffer(nullptr, 0) {}
  BlockBuffer(void* buffer, size_t size) : buffer_(buffer), size_(size) {}
  BlockBuffer(BlockBuffer&& rhs) : buffer_(rhs.buffer_), size_(rhs.size_) {
    rhs.buffer_ = nullptr;
    rhs.size_ = 0;
  }
  ~BlockBuffer() { free(buffer_); }

  const void* data() const { return buffer_; }
  size_t size() const { return size_; }

  void Reset() {
    free(buffer_);
    buffer_ = nullptr;
    size_ = 0;
  }

 private:
  BlockBuffer(BlockBuffer const& rhs) = delete;
  BlockBuffer& operator=(BlockBuffer const& rhs) = delete;

  void* buffer_;
  size_t size_;
};

class BlockBufferIO {
 public:
  explicit BlockBufferIO(BlockBuffer* bb) : bb_(bb) {}

  const void* GetReadPtrAndAdvance(size_t size) {
    size_t new_offset = offset_ + size;
    assert(new_offset <= bb_->size());
    const void* data = reinterpret_cast<const uint8_t*>(bb_->data()) + offset_;
    offset_ = new_offset;
    return data;
  }

  void Read(void* buffer, size_t size) {
    auto data = GetReadPtrAndAdvance(size);
    memcpy(buffer, data, size);
  }

  template <typename T>
  void Read(T& out) {
    Read(reinterpret_cast<void*>(&out), sizeof(T));
  }

  void Reset(BlockBuffer* bb = nullptr) {
    bb_ = bb;
    offset_ = 0;
  }

 private:
  BlockBuffer* bb_ = nullptr;
  size_t offset_ = 0;
};

class ChunkIO {
 public:
  ssize_t available() const { return available_; }

  uint8_t* GetCheckedReadPtr(ssize_t size) {
    assert(size <= available_);
    return chunk_.data + offset_;
  }

  void CommitRead(ssize_t size) {
    assert(size >= 0 && size <= available_);
    off_t new_offset = offset_ + size;
    ssize_t new_available = available_ - size;
    assert(new_offset >= offset_);
    assert(new_available <= available_);
    offset_ = new_offset;
    available_ = new_available;
  }

  void Read(void* buffer, size_t size) {
    auto data = GetCheckedReadPtr(size);
    memcpy(buffer, data, size);
    CommitRead(size);
  }

  template <typename T>
  void Read(T& out) {
    Read(reinterpret_cast<void*>(&out), sizeof(T));
  }

  std::pair<uint8_t*, ssize_t> ResetForWrite(ssize_t io_bytes_available) {
    assert(io_bytes_available > ssize_t(sizeof(chunk_.data_crc32)));
    ssize_t io_size = std::min(ssize_t(sizeof(chunk_)), io_bytes_available);
    offset_ = 0;
    available_ = io_size - sizeof(chunk_.data_crc32);
    return std::make_pair(reinterpret_cast<uint8_t*>(&chunk_), io_size);
  }

  void ChecksumAndDieIfWrong() {
    uint32_t checksum = static_cast<uint32_t>(crc32(crc32(0L, Z_NULL, 0), chunk_.data, static_cast<uInt>(available_)));
    assert(checksum == chunk_.data_crc32);
  }

 private:
  ssize_t available_ = 0;
  off_t offset_ = 0;
  stored::Chunk chunk_;
};

#pragma mark -

class LzmaDecompressor {
 public:
  struct IO {
    virtual bool FillLzmaStream(lzma_stream& stream) = 0;
    virtual void ConsumeLzmaStream(lzma_stream& stream, bool final) = 0;
  };

  LzmaDecompressor(IO& io) : io_(io) {}
  void Decompress(lzma_vli filter);
  const lzma_stream& stream() const { return stream_; }

 private:
  void InitLzma1();
  void InitLzma2();

  template <typename T>
  void ReadFromStream(T& out);

  IO& io_;
  lzma_stream stream_;
};

void LzmaDecompressor::Decompress(lzma_vli filter) {
  stream_ = LZMA_STREAM_INIT;
  io_.FillLzmaStream(stream_);

  assert(filter == LZMA_FILTER_LZMA1 || filter == LZMA_FILTER_LZMA2);
  if (filter == LZMA_FILTER_LZMA1) {
    InitLzma1();
  } else {
    InitLzma2();
  }

  lzma_ret ret = LZMA_OK;
  lzma_action action = LZMA_RUN;

  do {
    if (stream_.avail_in == 0 && action == LZMA_RUN) {
      bool eof = io_.FillLzmaStream(stream_);
      if (eof) {
        action = LZMA_FINISH;
      }
    }

    if (stream_.avail_out == 0) {
      io_.ConsumeLzmaStream(stream_, false);
    }

    ret = lzma_code(&stream_, action);
    assert(ret == LZMA_OK || ret == LZMA_STREAM_END);
  } while (ret == LZMA_OK);

  if (stream_.avail_out != 0) {
    io_.ConsumeLzmaStream(stream_, true);
  }

  lzma_end(&stream_);
}

void LzmaDecompressor::InitLzma1() {
  stored::Lzma1Header lzma_header;
  ReadFromStream(lzma_header);

  lzma_options_lzma lzma_options;
  memset(&lzma_options, 0, sizeof(lzma_options_lzma));

  assert(lzma_header.properties < (9 * 5 * 5));
  lzma_options.dict_size = lzma_header.dictionary_size;

  uint8_t properties = lzma_header.properties;
  lzma_options.lc = properties % 9;
  properties /= 9;
  lzma_options.pb = properties / 5;
  lzma_options.lp = properties % 5;

  lzma_filter filters[2] = {{LZMA_FILTER_LZMA1, &lzma_options}, {LZMA_VLI_UNKNOWN, 0}};
  lzma_ret ret = lzma_raw_decoder(&stream_, filters);
  assert(ret == LZMA_OK);
}

void LzmaDecompressor::InitLzma2() {
  stored::Lzma2Header lzma_header;
  ReadFromStream(lzma_header);

  lzma_options_lzma lzma_options;
  memset(&lzma_options, 0, sizeof(lzma_options_lzma));

  const uint8_t bits = lzma_header.properties & 0x3F;
  assert(bits <= 40);
  if (bits == 40) {
    lzma_options.dict_size = UINT32_MAX;
  } else {
    lzma_options.dict_size = 2 | (bits & 1);
    lzma_options.dict_size <<= bits / 2 + 11;
  }

  lzma_filter filters[2] = {{LZMA_FILTER_LZMA2, &lzma_options}, {LZMA_VLI_UNKNOWN, 0}};
  lzma_ret ret = lzma_raw_decoder(&stream_, filters);
  assert(ret == LZMA_OK);
}

template <typename T>
void LzmaDecompressor::ReadFromStream(T& out) {
  assert(stream_.avail_in > sizeof(out));
  memcpy(&out, stream_.next_in, sizeof(out));
  stream_.avail_in -= sizeof(out);
  stream_.next_in += sizeof(out);
}

#pragma mark -

class BlockReader : public LzmaDecompressor::IO {
 public:
  BlockReader(int fd, off_t offset) : fd_(fd), io_offset_(offset), decompressor_(*this) {}

  BlockBuffer ReadBlock();
  stored::BlockHeader header() const { return header_; }

 private:
  void ReadHeader();
  void ReadChunk();

  friend LzmaDecompressor;
  virtual bool FillLzmaStream(lzma_stream& stream) override;
  virtual void ConsumeLzmaStream(lzma_stream& stream, bool final) override;

  int fd_;
  off_t io_offset_;
  ssize_t io_bytes_read_ = 0;
  ssize_t io_bytes_left_ = 0;

  ChunkIO chunk_io_;
  stored::BlockHeader header_;

  LzmaDecompressor decompressor_;
};

void BlockReader::ReadHeader() {
  io_bytes_read_ = pread(fd_, &header_, sizeof(stored::BlockHeader), io_offset_);
  assert(io_bytes_read_ == sizeof(stored::BlockHeader));
  io_offset_ += io_bytes_read_;

  uint32_t checksum = static_cast<uint32_t>(
      crc32(crc32(0L, Z_NULL, 0), (uint8_t*)&header_.inner_header, sizeof(stored::BlockInnerHeader)));
  assert(checksum == header_.inner_header_crc32);

  io_bytes_left_ = header_.inner_header.data_size;
}

void BlockReader::ReadChunk() {
  assert(chunk_io_.available() == 0);
  assert(io_bytes_left_ > 0);

  auto io_pair = chunk_io_.ResetForWrite(io_bytes_left_);

  io_bytes_read_ = pread(fd_, io_pair.first, io_pair.second, io_offset_);
  assert(io_bytes_read_ == io_pair.second);
  io_offset_ += io_bytes_read_;
  io_bytes_left_ -= io_bytes_read_;

  chunk_io_.ChecksumAndDieIfWrong();
}

bool BlockReader::FillLzmaStream(lzma_stream& stream) {
  chunk_io_.CommitRead(chunk_io_.available() - stream.avail_in);

  if (chunk_io_.available() == 0) {
    ReadChunk();
  }

  stream.avail_in = chunk_io_.available();
  stream.next_in = chunk_io_.GetCheckedReadPtr(stream.avail_in);
  assert(stream.avail_in > 0);

  return io_bytes_left_ == 0;
}

void BlockReader::ConsumeLzmaStream(lzma_stream& stream, bool final) {
  if (final) {
    return;
  }

  assert(stream.avail_out == 0);
  assert((stream.next_out == nullptr && stream.total_out == 0) || stream.next_out != nullptr);
  uint8_t* buffer = stream.next_out - stream.total_out;
  size_t increment = std::max((size_t)(io_bytes_left_ * 1.25), 0x10000ul);
  buffer = (uint8_t*)reallocf(buffer, stream.total_out + increment);

  stream.next_out = buffer + stream.total_out;
  stream.avail_out = increment;
}

BlockBuffer BlockReader::ReadBlock() {
  ReadHeader();
  decompressor_.Decompress(LZMA_FILTER_LZMA1);
  const auto& lzma_stream = decompressor_.stream();
  BlockBuffer buffer(lzma_stream.next_out - lzma_stream.total_out, lzma_stream.total_out);
  return buffer;
}

#pragma mark -

class BaseParser {
 public:
  virtual bool Probe(int fd) const = 0;
  virtual void Parse(int fd) = 0;
  virtual ChecksumMethod checksum_method() const = 0;
  virtual off_t file_data_offset() const = 0;

  CompressionMethod compression_method() const { return compression_method_; }
  const std::vector<File>& files() const { return files_; }

 protected:
  void ReadStoredStruct(BlockBufferIO& bbio,
                        void* out_data,
                        size_t data_size,
                        size_t n_unicode,
                        size_t n_ascii,
                        std::vector<std::string>* out_strings) const {
    static std::wstring_convert<std::codecvt_utf8_utf16<std::u16string::value_type>, std::u16string::value_type>
        string_codec;

    size_t string_index = 0;
    for (size_t iter = 0; iter != n_unicode; ++iter, ++string_index) {
      uint32_t l;
      bbio.Read(l);
      if (l == 0) {
        if (out_strings) {
          out_strings->emplace_back();
        }
        continue;
      }
      auto string = reinterpret_cast<std::u16string::value_type const*>(bbio.GetReadPtrAndAdvance(l));
      if (out_strings) {
        auto string_end = reinterpret_cast<std::u16string::value_type const*>(bbio.GetReadPtrAndAdvance(0));
        auto string_utf8 = string_codec.to_bytes(string, string_end);
        out_strings->emplace_back(string_utf8);
      }
    }

    for (size_t iter = 0; iter != n_ascii; ++iter, ++string_index) {
      uint32_t l;
      bbio.Read(l);
      if (l == 0) {
        if (out_strings) {
          out_strings->emplace_back();
        }
        continue;
      }
      auto string = reinterpret_cast<const char*>(bbio.GetReadPtrAndAdvance(l));
      if (out_strings) {
        out_strings->emplace_back(string, l);
      }
    }

    if (out_data) {
      bbio.Read(out_data, data_size);
    } else {
      bbio.GetReadPtrAndAdvance(data_size);
    }
  }

  CompressionMethod compression_method_;
  std::vector<File> files_;
};

template <typename Version>
class Parser : public BaseParser {
 private:
  template <typename StoredStruct>
  void ReadStoredStruct(BlockBufferIO& bbio, StoredStruct* out_struct, bool store_strings = false) const {
    BaseParser::ReadStoredStruct(bbio,
                                 (out_struct) ? &out_struct->data : nullptr,
                                 sizeof(out_struct->data),
                                 StoredStruct::N_UNICODE_STRINGS,
                                 StoredStruct::N_ASCII_STRINGS,
                                 (out_struct && store_strings) ? &out_struct->strings : nullptr);
  }

 public:
  virtual bool Probe(int fd) const override {
    char banner[Version::SETUP_DATA_BANNER_SIZE];
    pread(fd, &banner, sizeof(banner), Version::SETUP_DATA_BANNER_OFFSET);
    return strcmp(banner, Version::SETUP_DATA_BANNER) == 0;
  }

  virtual void Parse(int fd) override {
    off_t base_offset = Version::SETUP_DATA_BANNER_OFFSET + Version::SETUP_DATA_BANNER_SIZE;

    auto block_reader = std::unique_ptr<BlockReader>(new BlockReader(fd, base_offset));
    auto setup_block_buffer = block_reader->ReadBlock();
    auto setup_block_header = block_reader->header();
    auto bbio = BlockBufferIO(&setup_block_buffer);

    typename Version::SetupHeader setup_header;
    ReadStoredStruct(bbio, &setup_header);
    assert(setup_header.data.file_count > 0);
    assert(setup_header.data.file_location_count > 0);

    compression_method_ = CompressionMethod(setup_header.data.compression_method);

    for (uint32_t i = 0; i != setup_header.data.language_count; ++i) {
      ReadStoredStruct<typename Version::Language>(bbio, nullptr);
    }
    for (uint32_t i = 0; i != setup_header.data.custom_message_count; ++i) {
      ReadStoredStruct<typename Version::CustomMessage>(bbio, nullptr);
    }
    for (uint32_t i = 0; i != setup_header.data.permission_count; ++i) {
      ReadStoredStruct<typename Version::Permission>(bbio, nullptr);
    }
    for (uint32_t i = 0; i != setup_header.data.type_count; ++i) {
      ReadStoredStruct<typename Version::Type>(bbio, nullptr);
    }
    for (uint32_t i = 0; i != setup_header.data.component_count; ++i) {
      ReadStoredStruct<typename Version::Component>(bbio, nullptr);
    }
    for (uint32_t i = 0; i != setup_header.data.task_count; ++i) {
      ReadStoredStruct<typename Version::Task>(bbio, nullptr);
    }
    for (uint32_t i = 0; i != setup_header.data.dir_count; ++i) {
      ReadStoredStruct<typename Version::Dir>(bbio, nullptr);
    }
    auto file_entries = std::vector<typename Version::File>(setup_header.data.file_count);
    for (uint32_t i = 0; i != setup_header.data.file_count; ++i) {
      ReadStoredStruct(bbio, &file_entries[i], true);
    }

    off_t file_location_block_offset =
        base_offset + sizeof(stored::BlockHeader) + setup_block_header.inner_header.data_size;
    block_reader = std::unique_ptr<BlockReader>(new BlockReader(fd, file_location_block_offset));
    auto file_location_block_buffer = block_reader->ReadBlock();
    bbio.Reset(&file_location_block_buffer);
    auto file_locations = std::vector<typename Version::FileLocation>(setup_header.data.file_location_count);
    for (uint32_t i = 0; i != setup_header.data.file_location_count; ++i) {
      ReadStoredStruct(bbio, &file_locations[i]);
    }

    for (size_t index = 0, end = file_entries.size(); index != end; ++index) {
      auto& fe = file_entries[index];
      auto& filename = fe.strings[stored::File::FILENAME_STRING_INDEX];

      if (filename.size() < 4)
        continue;
      const char* extension = &filename[filename.size() - 4];
      if (extension[0] != '.' || tolower(extension[1]) != 'm' || tolower(extension[2]) != 'h' ||
          tolower(extension[3]) != 'k')
        continue;

      assert(fe.data.file_location_index != UINT32_MAX);

      auto& fle = file_locations[fe.data.file_location_index];
      assert(fle.data.chunk_suboffset == 0);
      assert(fle.data.first_slice == 0);
      assert(fle.data.last_slice == 0);
      assert(fle.data.flags & stored::FileLocation::Flags::ChunkCompressed);
      assert((fle.data.flags & stored::FileLocation::Flags::CallInstructionOptimized) == 0);
      assert((fle.data.flags & stored::FileLocation::Flags::ChunkEncrypted) == 0);

      files_.emplace_back();
      auto& file = files_.back();
      file.filename = std::move(filename);
      file.original_size = fle.data.original_size;
      file.stored_size = fle.data.stored_size;
      file.stored_offset = fle.data.stored_offset;
      file.checksum = fle.data.checksum;
    }
  }

  virtual ChecksumMethod checksum_method() const override { return Version::CHECKSUM_METHOD; }
  virtual off_t file_data_offset() const override { return Version::FILE_DATA_OFFSET; }
};

#pragma mark -

struct ChecksumEngine {
  virtual void Initialize() = 0;
  virtual void Update(void* data, size_t size) = 0;
  virtual void Finalize(File::Checksum& checksum) = 0;
  virtual bool Equal(const File::Checksum& lhs, const File::Checksum& rhs) const = 0;
};

struct MD5Engine : public ChecksumEngine {
  virtual void Initialize() override { CC_MD5_Init(&ctx_); }
  virtual void Update(void* data, size_t size) override { CC_MD5_Update(&ctx_, data, CC_LONG(size)); }
  virtual void Finalize(File::Checksum& checksum) override { CC_MD5_Final(checksum.md5_.data, &ctx_); }
  virtual bool Equal(const File::Checksum& lhs, const File::Checksum& rhs) const override {
    return memcmp(lhs.md5_.data, rhs.md5_.data, sizeof(lhs.md5_.data)) == 0;
  }
  CC_MD5_CTX ctx_;
};

struct SHA1Engine : public ChecksumEngine {
  virtual void Initialize() override { CC_SHA1_Init(&ctx_); }
  virtual void Update(void* data, size_t size) override { CC_SHA1_Update(&ctx_, data, CC_LONG(size)); }
  virtual void Finalize(File::Checksum& checksum) override { CC_SHA1_Final(checksum.sha1_.data, &ctx_); }
  virtual bool Equal(const File::Checksum& lhs, const File::Checksum& rhs) const override {
    return memcmp(lhs.sha1_.data, rhs.sha1_.data, sizeof(lhs.sha1_.data)) == 0;
  }
  CC_SHA1_CTX ctx_;
};

#pragma mark -

class FileWriter : public LzmaDecompressor::IO {
 public:
  typedef std::function<void(FileWriter& writer, ssize_t bytes_written)> ProgressCallback;

  FileWriter(int input_fd, const BaseParser* parser, ProgressCallback callback);

  void Write(const File& file, int output_fd);
  size_t total_bytes_written() const { return decompressor_.stream().total_out; }

 private:
  static const size_t INPUT_BUFFER_SIZE = 0x2000;
  static const size_t OUTPUT_BUFFER_SIZE = 0x4000;

  ssize_t ReadInput(void* buffer, size_t bytes);

  friend LzmaDecompressor;
  virtual bool FillLzmaStream(lzma_stream& stream) override;
  virtual void ConsumeLzmaStream(lzma_stream& stream, bool final) override;

  ProgressCallback callback_;

  int in_fd_;
  int out_fd_;

  const off_t base_in_offset_;
  off_t in_offset_;
  size_t in_bytes_left_;

  MD5Engine md5_engine_;
  SHA1Engine sha1_engine_;
  ChecksumEngine* checksum_engine_;

  lzma_vli lzma_filter_;
  LzmaDecompressor decompressor_;

  uint8_t in_buffer_[INPUT_BUFFER_SIZE];
  uint8_t out_buffer_[OUTPUT_BUFFER_SIZE];
};

FileWriter::FileWriter(int in_fd, const BaseParser* parser, ProgressCallback callback)
    : callback_(callback), in_fd_(in_fd), base_in_offset_(parser->file_data_offset()), decompressor_(*this) {
  auto checksum_method = parser->checksum_method();
  assert(checksum_method == ChecksumMethod::MD5 || checksum_method == ChecksumMethod::SHA1);
  if (checksum_method == ChecksumMethod::MD5) {
    checksum_engine_ = &md5_engine_;
  } else {
    checksum_engine_ = &sha1_engine_;
  }

  auto compression_method = parser->compression_method();
  assert(compression_method == CompressionMethod::LZMA || compression_method == CompressionMethod::LZMA2);
  if (parser->compression_method() == CompressionMethod::LZMA) {
    lzma_filter_ = LZMA_FILTER_LZMA1;
  } else {
    lzma_filter_ = LZMA_FILTER_LZMA2;
  }
}

ssize_t FileWriter::ReadInput(void* buffer, size_t bytes) {
  ssize_t bytes_read = pread(in_fd_, buffer, bytes, in_offset_);
  assert(bytes_read == ssize_t(bytes));
  in_offset_ += bytes_read;
  in_bytes_left_ -= bytes_read;
  return bytes_read;
}

bool FileWriter::FillLzmaStream(lzma_stream& stream) {
  assert(stream.avail_in == 0);

  size_t bytes_to_read = std::min(sizeof(in_buffer_), in_bytes_left_);
  ssize_t bytes_read = ReadInput(in_buffer_, bytes_to_read);

  stream.avail_in = bytes_read;
  stream.next_in = in_buffer_;

  return in_bytes_left_ == 0;
}

void FileWriter::ConsumeLzmaStream(lzma_stream& stream, bool final) {
  ssize_t bytes_to_write = sizeof(out_buffer_) - stream.avail_out;

  stream.avail_out = sizeof(out_buffer_);
  stream.next_out = out_buffer_;

  if (bytes_to_write <= 0 || stream.total_out == 0)
    return;

  ssize_t bytes_written = write(out_fd_, out_buffer_, bytes_to_write);
  assert(bytes_written == bytes_to_write);

  checksum_engine_->Update(out_buffer_, bytes_to_write);

  callback_(*this, bytes_written);
}

void FileWriter::Write(const File& file, int out_fd) {
  in_offset_ = base_in_offset_ + file.stored_offset;
  in_bytes_left_ = file.stored_size + sizeof(uint32_t);
  out_fd_ = out_fd;

  uint32_t magic;
  ReadInput(&magic, sizeof(uint32_t));
  assert(magic == stored::FILE_DATA_MAGIC);

  checksum_engine_->Initialize();
  decompressor_.Decompress(lzma_filter_);

  assert(total_bytes_written() == file.original_size);

  File::Checksum out_checksum;
  checksum_engine_->Finalize(out_checksum);
  assert(checksum_engine_->Equal(out_checksum, file.checksum));
}

#pragma mark -

static std::atomic<size_t> global_file_index = ATOMIC_VAR_INIT(0);
static std::atomic<size_t> global_bytes_written = ATOMIC_VAR_INIT(0);
static std::atomic_flag cout_lock = ATOMIC_FLAG_INIT;

static void WriterThread(const int fd, const BaseParser* parser, const std::vector<File>& files) {
  auto writer = std::unique_ptr<FileWriter>(new FileWriter(
      fd, parser, [&](FileWriter& writer, ssize_t bytes_written) { global_bytes_written += bytes_written; }));

  size_t local_index;
  while ((local_index = global_file_index++) < files.size()) {
    auto& file = files.at(local_index);

    auto output_filename = file.filename.substr(file.filename.find_last_of('\\') + 1);
    assert(output_filename.size() > 0);

    while (cout_lock.test_and_set(std::memory_order_acquire)) {
    }
    std::cout << output_filename << std::endl;
    cout_lock.clear(std::memory_order_release);

    int output_fd = open(output_filename.c_str(), O_CREAT | O_TRUNC | O_WRONLY, 0664);
    assert(output_fd != -1);
    fcntl(output_fd, F_NOCACHE, 1);

    fstore_t fst;
    fst.fst_flags = F_ALLOCATEALL;
    fst.fst_posmode = F_PEOFPOSMODE;
    fst.fst_offset = 0;
    fst.fst_length = file.original_size;
    fcntl(output_fd, F_PREALLOCATE, &fst);

    writer->Write(file, output_fd);
    close(output_fd);
  }
}

int main(int argc, const char* argv[]) {
  if (argc < 2) {
    std::cerr << "usage: << " << argv[0] << " <file>" << std::endl;
    exit(1);
  }

  int fd = open(argv[1], O_RDONLY);
  if (fd == -1) {
    std::cerr << "failed to open '" << argv[1] << "': " << strerror(errno) << std::endl;
    exit(1);
  }
  fcntl(fd, F_NOCACHE, 1);

  std::vector<BaseParser*> parsers{new Parser<v523>(), new Parser<v550>()};
  BaseParser* parser = nullptr;
  for (auto& candidate : parsers) {
    if (candidate->Probe(fd)) {
      parser = candidate;
      break;
    }
  }
  if (!parser) {
    std::cerr << "no parser matched" << std::endl;
    exit(1);
  }

  parser->Parse(fd);
  auto& files = parser->files();

  double total_size_out = 0;
  for (auto& file : files) {
    total_size_out += file.original_size;
  }

  auto concurrency = std::thread::hardware_concurrency();
  std::vector<std::thread> threads;
  for (size_t i = 0; i < concurrency; ++i) {
    threads.emplace_back(std::thread(WriterThread, fd, parser, files));
  }

  std::atomic<bool> exit_status = ATOMIC_VAR_INIT(false);
  auto status_thread = std::thread([&] {
    size_t local_bytes_written = global_bytes_written;
    while (local_bytes_written < total_size_out && !exit_status) {
      while (cout_lock.test_and_set(std::memory_order_acquire)) {
      }
      std::cout << "<< " << local_bytes_written / total_size_out << std::endl;
      cout_lock.clear(std::memory_order_release);
      std::this_thread::sleep_for(std::chrono::seconds(1));
      local_bytes_written = global_bytes_written;
    }
  });

  for (auto& thread : threads) {
    thread.join();
  }
  exit_status = true;
  status_thread.join();

  close(fd);

  return 0;
}
