//
//  unpackgogsetup.cpp
//  unpackgogsetup
//
//  Created by Jean-François Roy on 28/12/2011.
//  Copyright (c) 2012. All rights reserved.
//

#include <iostream>
#include <memory>
#include <string>
#include <utility>
#include <vector>
#include <cassert>

#include <unistd.h>
#include <fcntl.h>
#include <errno.h>
#include <Block.h>

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdocumentation"
#include <lzma.h>
#pragma clang diagnostic pop
#include <zlib.h>

// magic constants

static const char* INNO_SETUP_SETUP_DATA_BANNER = "Inno Setup Setup Data (5.2.3)";
static const off_t INNO_SETUP_SETUP_DATA_BANNER_OFFSET = 0x69C42BC3;
static const size_t INNO_SETUP_SETUP_DATA_BANNER_SIZE = 64ul;
static const off_t INNO_SETUP_FILE_DATA_OFFSET = 0x164C00;
static const uint32_t INNO_SETUP_FILE_DATA_MAGIC = 0x1A626C7A; // zlb\1A

// these structures match on-disk data

struct StoredInnoSetupVersionData {
  uint32_t winVersion;
  uint32_t ntVersion;
  uint16_t ntServicePack;
} __attribute__((packed));

struct StoredInnoSetupHeader {
  uint8_t stuff[32];
  uint32_t numLanguageEntries;
  uint32_t numCustomMessageEntries;
  uint32_t numPermissionEntries;
  uint32_t numTypeEntries;
  uint32_t numComponentEntries;
  uint32_t numTaskEntries;
  uint32_t numDirEntries;
  uint32_t numFileEntries;
  uint32_t numFileLocationEntries;
  uint32_t numIconEntries;
  uint32_t numIniEntries;
  uint32_t numRegistryEntries;
  uint32_t numInstallDeleteEntries;
  uint32_t numUninstallDeleteEntries;
  uint32_t numRunEntries;
  uint32_t numUninstallRunEntries;
  uint8_t moreStuff[206];
} __attribute__((packed));

struct StoredInnoFileEntry {
  static const int STRING_COUNT = 9;

  StoredInnoSetupVersionData minVersion;
  StoredInnoSetupVersionData onlyBelowVersion;
  uint32_t locationEntry;
  uint32_t attributes;
  uint64_t externalSize;
  uint16_t permissionEntry;
  uint8_t options;
  uint32_t fileType;
} __attribute__((packed));

struct StoredInnoFileLocationEntry {
  enum Flags {
    versionInfoValid = 1 << 0,
    versionInfoNotValid = 1 << 1,
    timeStampInUTC = 1 << 2,
    isUninstExe = 1 << 3,
    callInstructionOptimized = 1 << 4,
    touch = 1 << 5,
    chunkEncrypted = 1 << 6,
    chunkCompressed = 1 << 7,
    solidBreak = 1 << 8
  };

  uint32_t firstSlice;
  uint32_t lastSlice;
  uint32_t startOffset;
  uint64_t chunkSubOffset;
  uint64_t originalSize;
  uint64_t chunkCompressedSize;
  uint8_t md5Sum[16];
  uint64_t timestamp;
  uint32_t fileVersionMS;
  uint32_t fileVersionLS;
  uint16_t flags;
} __attribute__((packed));

struct StoredBlockInnerHeader {
  uint32_t blockPayloadStoreSize;
  uint8_t compressed;
} __attribute__((packed));

struct StoredBlockHeader {
  uint32_t innerHeaderCrc32;
  StoredBlockInnerHeader innerHeader;
} __attribute__((packed));

struct StoredChunk {
  static const int MAX_CHUNK_PAYLOAD_SIZE = 0x1000ul;

  uint32_t payloadCrc32;
  uint8_t payload[MAX_CHUNK_PAYLOAD_SIZE];
} __attribute__((packed));

struct StoredLzmaHeader {
  uint8_t properties;
  uint32_t dictSize;
} __attribute__((packed));

// functional (runtime) classes

class BlockBuffer {
public:
  BlockBuffer(void* buffer, size_t size) : _buffer(buffer), _size(size) {}
  BlockBuffer(BlockBuffer&& rhs) : _buffer(rhs._buffer), _size(rhs._size)
  {
    rhs._buffer = nullptr;
    rhs._size = 0ul;
  }
  ~BlockBuffer()
  {
    if (_buffer)
      free(_buffer);
  }
  BlockBuffer(BlockBuffer const& rhs) = delete;
  BlockBuffer& operator=(BlockBuffer const& rhs) = delete;

  void* data() { return _buffer; }
  size_t size() const { return _size; }

private:
  void* _buffer;
  size_t _size;
};

class BlockReaderLzma;

class Chunk {
  friend class BlockReaderLzma;

public:
  void advance(size_t s)
  {
    _available -= s;
    _offset += s;
  }
  uint32_t available() const { return _available; }

  uint8_t* read_ptr() { return _chunk.payload + _offset; }
  uint8_t* read_advance(size_t s)
  {
    assert(available() >= s);
    uint8_t* p = _chunk.payload + _offset;
    advance(s);
    return p;
  }

private:
  uint32_t _available;
  uint32_t _offset;
  StoredChunk _chunk;
};

class BlockReaderLzma {
public:
  BlockReaderLzma(int fd, off_t offset) : _fd(fd), _ioOffset(offset), _ioBytesRead(0l), _ioBytesLeft(0ul), _chunk(), _header() {}

  BlockBuffer read();
  StoredBlockHeader header() const { return _header; }

private:
  void _read_header();
  void _read_chunk();

  void _init_lzma();
  void _grow_lzma_output_buffer();

  // --

  int _fd;
  off_t _ioOffset;
  ssize_t _ioBytesRead;
  ssize_t _ioBytesLeft;

  lzma_stream _lzmaStream;

  Chunk _chunk;
  StoredBlockHeader _header;
};

void BlockReaderLzma::_read_header()
{
  _ioBytesRead = pread(_fd, &_header, sizeof(StoredBlockHeader), _ioOffset);
  assert(_ioBytesRead == sizeof(StoredBlockHeader));
  _ioOffset += _ioBytesRead;

  uint32_t checksum = static_cast<uint32_t>(crc32(crc32(0L, Z_NULL, 0), (uint8_t*)&_header.innerHeader, sizeof(StoredBlockInnerHeader)));
  assert(checksum == _header.innerHeaderCrc32);

  _ioBytesLeft = _header.innerHeader.blockPayloadStoreSize;
}

void BlockReaderLzma::_read_chunk()
{
  assert(_chunk.available() == 0u);

  _chunk._available = static_cast<uint32_t>(std::min<ssize_t>(StoredChunk::MAX_CHUNK_PAYLOAD_SIZE, _ioBytesLeft - sizeof(uint32_t)));
  size_t bytesToRead = _chunk._available + sizeof(uint32_t);
  assert(bytesToRead >= sizeof(uint32_t));

  _ioBytesRead = pread(_fd, &_chunk._chunk, bytesToRead, _ioOffset);
  assert(_ioBytesRead == static_cast<ssize_t>(bytesToRead));
  _ioOffset += _ioBytesRead;
  _ioBytesLeft -= _ioBytesRead;

  uint32_t checksum = static_cast<uint32_t>(crc32(crc32(0L, Z_NULL, 0), (uint8_t*)_chunk._chunk.payload, static_cast<uint32_t>(_chunk._available)));
  assert(checksum == _chunk._chunk.payloadCrc32);

  _chunk._offset = 0;
}

void BlockReaderLzma::_init_lzma()
{
  _read_chunk();

  StoredLzmaHeader* lh = (StoredLzmaHeader*)_chunk.read_advance(sizeof(StoredLzmaHeader));
  assert(lh->properties < (9 * 5 * 5));

  lzma_options_lzma lzma_options;
  memset(&lzma_options, 0, sizeof(lzma_options_lzma));

  uint8_t properties = lh->properties;
  lzma_options.dict_size = lh->dictSize;
  lzma_options.lc = properties % 9;
  properties /= 9;
  lzma_options.pb = properties / 5;
  lzma_options.lp = properties % 5;

  lzma_filter filters[2] = {{LZMA_FILTER_LZMA1, &lzma_options}, {LZMA_VLI_UNKNOWN, 0}, };

  memset(&_lzmaStream, 0, sizeof(lzma_stream));
  lzma_ret r = lzma_raw_decoder(&_lzmaStream, filters);
  assert(r == LZMA_OK);
}

void BlockReaderLzma::_grow_lzma_output_buffer()
{
  uint8_t* buffer = _lzmaStream.next_out - _lzmaStream.total_out;

  size_t increment = std::max((size_t)(_ioBytesLeft * 1.25), 0x10000ul);
  buffer = (uint8_t*)reallocf(buffer, _lzmaStream.total_out + increment);

  _lzmaStream.next_out = buffer + _lzmaStream.total_out;
  _lzmaStream.avail_out += increment;
}

BlockBuffer BlockReaderLzma::read()
{
  // read header
  _read_header();

  // init lzma decompression
  _init_lzma();

  // read everything
  _lzmaStream.avail_out = _header.innerHeader.blockPayloadStoreSize * 1.25;
  _lzmaStream.next_out = (uint8_t*)malloc(_lzmaStream.avail_out);

  lzma_ret ret = LZMA_OK;

  do {
    if (_lzmaStream.avail_in == 0) {
      if (_chunk.available() == 0)
        _read_chunk();

      _lzmaStream.avail_in = _chunk.available();
      _lzmaStream.next_in = _chunk.read_ptr();
    }

    ret = lzma_code(&_lzmaStream, LZMA_RUN);
    assert(ret == LZMA_OK);

    if (_lzmaStream.avail_out == 0) {
      _grow_lzma_output_buffer();
    }

    _chunk.advance(_chunk.available() - _lzmaStream.avail_in);
  } while (_ioBytesLeft > 0u);

  do {
    ret = lzma_code(&_lzmaStream, LZMA_FINISH);
    assert(ret == LZMA_OK || ret == LZMA_STREAM_END);

    if (_lzmaStream.avail_out == 0 && ret == LZMA_OK) {
      _grow_lzma_output_buffer();
    }
  } while (ret == LZMA_OK);

  BlockBuffer buffer(_lzmaStream.next_out - _lzmaStream.total_out, _lzmaStream.total_out);
  lzma_end(&_lzmaStream);

  return buffer;
}

// --

class CompressedFileDecompressorLzma {
public:
  typedef void (^ProgressBlock)(CompressedFileDecompressorLzma& decompressor);

  CompressedFileDecompressorLzma(int intputFD, off_t offset, size_t compressedSize, int outputFD, ProgressBlock progressCallback)
      : _intputFD(intputFD), _storedOffset(offset), _ioOffset(offset), _ioBytesLeft(compressedSize + sizeof(StoredLzmaHeader)), _outputFD(outputFD),
        _progressCallback(Block_copy(progressCallback)) {}

  ~CompressedFileDecompressorLzma() { Block_release(_progressCallback); }

  size_t decompress();
  lzma_stream& get_stream() { return _lzmaStream; }

private:
  static const size_t INPUT_BUFFER_SIZE = 0x8000;
  static const size_t OUTPUT_BUFFER_SIZE = 0x10000;

  ssize_t _read_input(void* buffer, size_t bytes);

  void _fill_input_buffer();
  void _write_output_buffer();

  void _init_lzma();
  void _grow_lzma_output_buffer();

  // --

  int _intputFD;
  off_t _storedOffset;

  off_t _ioOffset;
  size_t _ioBytesLeft;

  int _outputFD;
  ProgressBlock _progressCallback;

  lzma_stream _lzmaStream;

  uint8_t _lzmaInputBuffer[INPUT_BUFFER_SIZE];
  uint8_t _lzmaOutputBuffer[OUTPUT_BUFFER_SIZE];
};

ssize_t CompressedFileDecompressorLzma::_read_input(void* buffer, size_t bytes)
{
  ssize_t bytesRead = pread(_intputFD, buffer, bytes, _ioOffset);
  assert((size_t)bytesRead == bytes);
  _ioOffset += bytesRead;
  _ioBytesLeft -= bytesRead;
  return bytesRead;
}

void CompressedFileDecompressorLzma::_init_lzma()
{
  StoredLzmaHeader lh;
  _read_input(&lh, sizeof(StoredLzmaHeader));

  assert(lh.properties < (9 * 5 * 5));

  lzma_options_lzma lzma_options;
  memset(&lzma_options, 0, sizeof(lzma_options_lzma));

  uint8_t properties = lh.properties;
  lzma_options.dict_size = lh.dictSize;
  lzma_options.lc = properties % 9;
  properties /= 9;
  lzma_options.pb = properties / 5;
  lzma_options.lp = properties % 5;

  lzma_filter filters[2] = {{LZMA_FILTER_LZMA1, &lzma_options}, {LZMA_VLI_UNKNOWN, 0}, };

  memset(&_lzmaStream, 0, sizeof(lzma_stream));
  lzma_ret r = lzma_raw_decoder(&_lzmaStream, filters);
  assert(r == LZMA_OK);
}

void CompressedFileDecompressorLzma::_fill_input_buffer()
{
  assert(_lzmaStream.avail_in == 0);

  size_t bytesToRead = std::min((size_t)INPUT_BUFFER_SIZE, _ioBytesLeft);
  ssize_t bytesRead = _read_input(_lzmaInputBuffer, bytesToRead);

  _lzmaStream.avail_in = bytesRead;
  _lzmaStream.next_in = _lzmaInputBuffer;
}

void CompressedFileDecompressorLzma::_write_output_buffer()
{
  size_t bytesToWrite = _lzmaStream.next_out - _lzmaOutputBuffer;
  if (bytesToWrite == 0ul)
    return;

  ssize_t bytesWritten = write(_outputFD, _lzmaOutputBuffer, bytesToWrite);
  assert((size_t)bytesWritten == bytesToWrite);

  _lzmaStream.avail_out = OUTPUT_BUFFER_SIZE;
  _lzmaStream.next_out = _lzmaOutputBuffer;

  _progressCallback(*this);
}

size_t CompressedFileDecompressorLzma::decompress()
{
  // check the magic
  uint32_t magic;
  _read_input(&magic, sizeof(uint32_t));
  assert(magic == INNO_SETUP_FILE_DATA_MAGIC);

  // init lzma decompression
  _init_lzma();

  // stream everything
  _lzmaStream.avail_out = OUTPUT_BUFFER_SIZE;
  _lzmaStream.next_out = _lzmaOutputBuffer;

  _lzmaStream.avail_in = 0;
  _lzmaStream.next_in = nullptr;

  lzma_ret ret = LZMA_OK;

  do {
    if (_lzmaStream.avail_in == 0) {
      _fill_input_buffer();
    }

    ret = lzma_code(&_lzmaStream, LZMA_RUN);
    assert(ret == LZMA_OK || ret == LZMA_STREAM_END);

    if (_lzmaStream.avail_out == 0) {
      _write_output_buffer();
    }
  } while (_ioBytesLeft > 0u);

  do {
    ret = lzma_code(&_lzmaStream, LZMA_FINISH);
    assert(ret == LZMA_OK || ret == LZMA_STREAM_END);

    if (_lzmaStream.avail_out == 0 && ret == LZMA_OK) {
      _write_output_buffer();
    }
  } while (ret == LZMA_OK);

  _write_output_buffer();

  size_t totalOut = _lzmaStream.total_out;
  lzma_end(&_lzmaStream);

  return totalOut;
}

// -- main program

static void* parse_setup_buffer(void* buffer, size_t size, size_t nStrings, void* extraBuffer = nullptr, std::string* strings = nullptr)
{
  uint8_t* readBuffer = (uint8_t*)buffer;

  for (size_t i = 0; i != nStrings; ++i) {
    union {
      uint32_t* ui32;
      uint8_t* ui8;
    } u;
    u.ui8 = readBuffer;
    uint32_t l = *u.ui32;
    readBuffer += sizeof(uint32_t);
    if (l == 0)
      continue;

    if (strings)
      strings[i].assign((const char*)readBuffer, l);

    readBuffer += l;
  }

  size_t extraSize = size - nStrings * sizeof(uint32_t);
  if (extraBuffer)
    memcpy(extraBuffer, readBuffer, extraSize);

  return readBuffer + extraSize;
}

int main(int argc, const char* argv[])
{
  if (argc < 2) {
    std::cerr << "usage: << " << argv[0] << " <setup exe>" << std::endl;
    exit(1);
  }

  int fd = open(argv[1], O_RDONLY);
  if (fd == -1) {
    std::cerr << "failed to open '" << argv[1] << "': " << strerror(errno) << std::endl;
    exit(1);
  }

  // check the inno setup header
  char banner[INNO_SETUP_SETUP_DATA_BANNER_SIZE];
  pread(fd, &banner, sizeof(banner), INNO_SETUP_SETUP_DATA_BANNER_OFFSET);
  assert(strcmp(banner, INNO_SETUP_SETUP_DATA_BANNER) == 0);

  // read the setup header
  auto br = std::unique_ptr<BlockReaderLzma>(new BlockReaderLzma(fd, INNO_SETUP_SETUP_DATA_BANNER_OFFSET + sizeof(banner)));
  auto setupBlockBuffer = br->read();
  StoredBlockHeader setupBlockHeader = br->header();

  // process the setup header up to the file entries
  StoredInnoSetupHeader setupHeader;

  void* next = parse_setup_buffer(setupBlockBuffer.data(), 302, 29, &setupHeader);
  StoredInnoFileEntry* fileEntries = new StoredInnoFileEntry[setupHeader.numFileEntries];
  auto fileEntriesStrings = new std::vector<std::string>[setupHeader.numFileEntries];
  for (size_t i = 0, end = setupHeader.numFileEntries; i != end; ++i)
    fileEntriesStrings[i].resize(StoredInnoFileEntry::STRING_COUNT);

  for (uint32_t i = 0; i != setupHeader.numLanguageEntries; ++i)
    next = parse_setup_buffer(next, 65, 10);
  for (uint32_t i = 0; i != setupHeader.numCustomMessageEntries; ++i)
    next = parse_setup_buffer(next, 12, 2);
  for (uint32_t i = 0; i != setupHeader.numPermissionEntries; ++i)
    next = parse_setup_buffer(next, 4, 1);
  for (uint32_t i = 0; i != setupHeader.numTypeEntries; ++i)
    next = parse_setup_buffer(next, 46, 4);
  for (uint32_t i = 0; i != setupHeader.numComponentEntries; ++i)
    next = parse_setup_buffer(next, 62, 5);
  for (uint32_t i = 0; i != setupHeader.numTaskEntries; ++i)
    next = parse_setup_buffer(next, 50, 6);
  for (uint32_t i = 0; i != setupHeader.numDirEntries; ++i)
    next = parse_setup_buffer(next, 55, 7);
  for (uint32_t i = 0; i != setupHeader.numFileEntries; ++i)
    next = parse_setup_buffer(next, 79, StoredInnoFileEntry::STRING_COUNT, fileEntries + i, &fileEntriesStrings[i][0]);

  //    for (uint32_t i = 0; i != setupHeader.numIconEntries; ++i)
  //        next = parse_setup_buffer(next, 80, 12);
  //    for (uint32_t i = 0; i != setupHeader.numIniEntries; ++i)
  //        next = parse_setup_buffer(next, 61, 10);
  //    for (uint32_t i = 0; i != setupHeader.numRegistryEntries; ++i)
  //        next = parse_setup_buffer(next, 65, 9);
  //    for (uint32_t i = 0; i != setupHeader.numInstallDeleteEntries; ++i)
  //        next = parse_setup_buffer(next, 49, 7);
  //    for (uint32_t i = 0; i != setupHeader.numUninstallDeleteEntries; ++i)
  //        next = parse_setup_buffer(next, 49, 7);
  //    for (uint32_t i = 0; i != setupHeader.numRunEntries; ++i)
  //        next = parse_setup_buffer(next, 79, 13);
  //    for (uint32_t i = 0; i != setupHeader.numUninstallRunEntries; ++i)
  //        next = parse_setup_buffer(next, 79, 13);

  // read the file location block
  off_t fileLocationBlockOffset =
      INNO_SETUP_SETUP_DATA_BANNER_OFFSET + sizeof(banner) + sizeof(StoredBlockHeader) + setupBlockHeader.innerHeader.blockPayloadStoreSize;
  br = std::unique_ptr<BlockReaderLzma>(new BlockReaderLzma(fd, fileLocationBlockOffset));
  auto fileLocationBlockBuffer = br->read();
  br.reset();

  StoredInnoFileLocationEntry* fileLocationEntries = new StoredInnoFileLocationEntry[setupHeader.numFileLocationEntries];

  next = fileLocationBlockBuffer.data();
  for (uint32_t i = 0; i != setupHeader.numFileLocationEntries; ++i)
    next = parse_setup_buffer(next, 70, 0, fileLocationEntries + i);

  std::vector<uint32_t> fileEntryIndicesToUnpack;
  for (uint32_t i = 0; i != setupHeader.numFileEntries; ++i) {
    StoredInnoFileEntry& fe = fileEntries[i];
    std::string& filename = fileEntriesStrings[i][1];

    //        StoredInnoFileLocationEntry& fle = fileLocationEntries[fe.locationEntry];
    //        std::cout << i << ": " << filename << "\n";
    //        std::cout << "    " << "size=" << fle.originalSize << "\n";
    //        std::cout << "    " << "compressed size=" << fle.chunkCompressedSize << "\n";
    //        std::cout << "    " << "first slice=" << fle.firstSlice << " last slice=" << fle.lastSlice << "\n";
    //        std::cout << "    " << "start offset=" << fle.startOffset << " chunk suboffset=" << fle.chunkSubOffset << "\n";
    //        std::cout << "    " << "flags: ";
    //        if ((fle.flags & StoredInnoFileLocationEntry::Flags::callInstructionOptimized))
    //            std::cout << "callInstructionOptimized ";
    //        if ((fle.flags & StoredInnoFileLocationEntry::Flags::chunkCompressed))
    //            std::cout << "compressed ";
    //        if ((fle.flags & StoredInnoFileLocationEntry::Flags::chunkEncrypted))
    //            std::cout << "encrypted ";
    //        std::cout << "\n\n";

    if (fe.locationEntry == UINT32_MAX)
      continue;

    // only decompress MHK files
    if (filename.size() < 4)
      continue;
    char* extension = &filename[filename.size() - 4];
    if (extension[0] != '.' || tolower(extension[1]) != 'm' || tolower(extension[2]) != 'h' || tolower(extension[3]) != 'k')
      continue;

    fileEntryIndicesToUnpack.push_back(i);
  }

  std::cout << fileEntryIndicesToUnpack.size() << std::endl;

  for (auto i : fileEntryIndicesToUnpack) {
    StoredInnoFileEntry& fe = fileEntries[i];
    std::string& filename = fileEntriesStrings[i][1];
    StoredInnoFileLocationEntry& fle = fileLocationEntries[fe.locationEntry];

    // use the last component of the filename for the output
    const char* filename_c = filename.c_str();
    const char* filenameLastComponent = strrchr(filename_c, '\\');
    if (filenameLastComponent)
      filenameLastComponent += 1;

    assert(fle.chunkSubOffset == 0);
    assert(fle.flags & StoredInnoFileLocationEntry::Flags::chunkCompressed);
    assert((fle.flags & StoredInnoFileLocationEntry::Flags::callInstructionOptimized) == 0);
    assert((fle.flags & StoredInnoFileLocationEntry::Flags::chunkEncrypted) == 0);

    std::cout << filenameLastComponent << std::endl;

    int outputFD = open(filenameLastComponent, O_CREAT | O_WRONLY, 0664);
    assert(outputFD != -1);

    __block float nextThreshold = 0.1f;
    CompressedFileDecompressorLzma::ProgressBlock outputProgress = ^(CompressedFileDecompressorLzma & decompressor)
    {
      float progress = std::min(1.0f, (float)decompressor.get_stream().total_out / fle.originalSize);
      if (progress >= nextThreshold) {
        std::cout << "<< " << progress << std::endl;
        nextThreshold = std::min(1.0f, progress + 0.1f);
      }
    };

    auto decompressor = std::unique_ptr<CompressedFileDecompressorLzma>(
        new CompressedFileDecompressorLzma(fd, INNO_SETUP_FILE_DATA_OFFSET + fle.startOffset, fle.chunkCompressedSize, outputFD, outputProgress));

    ssize_t bytesWritten = decompressor->decompress();
    assert((uint64_t)bytesWritten == fle.originalSize);
    close(outputFD);
  }

  close(fd);

  return 0;
}
