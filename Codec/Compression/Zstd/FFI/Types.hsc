-- Copyright (c) 2016-present, Facebook, Inc.
-- All rights reserved.
--
-- This source code is licensed under the BSD-style license found in
-- the LICENSE file in the root directory of this source tree. An
-- additional grant of patent rights can be found in the PATENTS file
-- in the same directory.

{-# LANGUAGE ExistentialQuantification #-}

-- |
-- Module      : Codec.Compression.Zstd.FFI
-- Copyright   : (c) 2016-present, Facebook, Inc. All rights reserved.
--
-- License     : BSD3
-- Maintainer  : bos@serpentine.com
-- Stability   : experimental
-- Portability : GHC
--
-- Types and functions that support the low-level FFI bindings.

module Codec.Compression.Zstd.FFI.Types
    (
      Buffer(..)
    , In
    , Out
    , CCtx
    , DCtx
    , CDict
    , DDict
    , peekPtr
    , pokePtr
    , peekSize
    , pokeSize
    , peekPos
    , pokePos
    , zstd_c_compressionLevel
    , zstd_c_nbWorkers
    , zstd_c_jobSize
    , zstd_c_overlapLog
    , zstd_e_continue
    , zstd_e_flush
    , zstd_e_end
    , zstd_reset_session_only
    , zstd_reset_parameters
    , zstd_reset_session_and_parameters
    ) where

#define ZSTD_STATIC_LINKING_ONLY
#include <zstd.h>

import Foreign.C.Types (CInt(..), CSize(..))
import Foreign.Storable
import GHC.Ptr (Ptr(..))

-- | An opaque compression context structure.
data CCtx
-- | An opaque decompression context structure.
data DCtx

-- | An opaque pre-digested compression dictionary structure.
data CDict
-- | An opaque pre-digested decompression dictionary structure.
data DDict

-- | A tag type to indicate that a 'Buffer' is used for tracking input.
data In
-- | A tag type to indicate that a 'Buffer' is used for tracking output.
data Out

-- | A streaming buffer type. The type parameter statically indicates
-- whether the buffer is used to track an input or output buffer.
data Buffer io = forall a. Buffer {
      -- | Pointer to the start of the buffer.  This can be set once
      -- by the caller, and read by the streaming function.
      bufPtr  :: {-# UNPACK #-} !(Ptr a)
      -- | Size of the buffer (in bytes).  This can be set once by the
      -- caller, and is read by the streaming function.
    , bufSize :: {-# UNPACK #-} !CSize
      -- | Current offset into the buffer (in bytes).  This must be
      -- initially set to zero by the caller, and is updated by the
      -- streaming function.
    , bufPos  :: {-# UNPACK #-} !CSize
    }

instance Storable (Buffer io) where
    sizeOf _     = #const sizeof(ZSTD_inBuffer)
    alignment _  = alignment (undefined :: CInt)

    peek p = do
      ptr <- (#peek ZSTD_inBuffer, src) p
      size <- (#peek ZSTD_inBuffer, size) p
      pos <- (#peek ZSTD_inBuffer, pos) p
      return (Buffer ptr size pos)

    poke p (Buffer ptr size pos) = do
      (#poke ZSTD_inBuffer, src) p ptr
      (#poke ZSTD_inBuffer, size) p size
      (#poke ZSTD_inBuffer, pos) p pos

-- | Read the 'bufPtr' value from a 'Buffer'.
peekPtr :: Ptr (Buffer io) -> IO CSize
peekPtr p = (#peek ZSTD_inBuffer, src) p

-- | Write to the 'bufPtr' value in a 'Buffer'.
pokePtr :: Ptr (Buffer io) -> Ptr a -> IO ()
pokePtr dst p = (#poke ZSTD_inBuffer, src) dst p

-- | Read the 'bufSize' value from a 'Buffer'.
peekSize :: Ptr (Buffer io) -> IO CSize
peekSize p = (#peek ZSTD_inBuffer, size) p

-- | Write to the 'bufSize' value in a 'Buffer'.
pokeSize :: Ptr (Buffer io) -> CSize -> IO ()
pokeSize dst s = (#poke ZSTD_inBuffer, size) dst s

-- | Read the 'bufPos' value from a 'Buffer'.
peekPos :: Ptr (Buffer io) -> IO CSize
peekPos p = (#peek ZSTD_inBuffer, pos) p

-- | Write to the 'bufPos' value in a 'Buffer'.
pokePos :: Ptr (Buffer io) -> CSize -> IO ()
pokePos dst s = (#poke ZSTD_inBuffer, pos) dst s

-- | @ZSTD_c_compressionLevel@ compression parameter, sets the compression
-- level.
zstd_c_compressionLevel :: CInt
zstd_c_compressionLevel = #const ZSTD_c_compressionLevel

-- | @ZSTD_c_nbWorkers@ compression parameter, sets the number of workers.
--
-- * @0@: single-threaded (default)
-- * @N@: multi-threaded mode, using up to @N@ worker threads
zstd_c_nbWorkers :: CInt
zstd_c_nbWorkers = #const ZSTD_c_nbWorkers

-- | @ZSTD_c_jobSize@ compression parameter, sets the size of a compression job.
-- 
-- @0@ lets zstd pick a default.
--
-- /NOTE/: Job size must be a minimum of overlap size, or @ZSTDMT_JOBSIZE_MIN@
-- (512 KB), whichever is largest.
--
-- /NOTE/: Only takes effect when @ZSTD_c_nbWorkers >= 1@.
zstd_c_jobSize :: CInt
zstd_c_jobSize = #const ZSTD_c_jobSize

-- | @ZSTD_c_overlapLog@ compression parameter, sets the overlap of consecutive
-- jobs in multi-threaded mode, as a fraction of window size; larger values
-- increase compression ratio, but decrease speed.
--
-- Range @0..9@:
--
-- * @0@ = library default, varies between 6 and 9 depending on compression strategy
-- * @1@ = no overlap
-- * @9@ = full window
--
-- Each intermediate rank halves the previous overlap:
--
-- * @9@: @w@
-- * @8@: @w\/2@
-- * @7@: @w\/4@
--
-- ...and so on until @1@ (none).
zstd_c_overlapLog :: CInt
zstd_c_overlapLog = #const ZSTD_c_overlapLog

-- | @ZSTD_e_continue@ streaming compression parameter, indicates that the
-- encoder should buffer internally and decide when to return the compressed
-- result.
--
-- Provides better compression at the expense of less regular streaming output.
--
-- /NOTE/: When @ZSTD_c_nbWorkers >= 1@, @ZSTD_e_continue@ is non-blocking.
zstd_e_continue :: CInt
zstd_e_continue = #const ZSTD_e_continue

-- | @ZSTD_e_flush@ streaming compression parameter, indicates that the encoder
-- should flush any buffered data to the output and create (at least) one new
-- block (which can be decoded immediately upon reception).
--
-- The frame will continue, and future data can reference previously compressed
-- data (improving compression).
--
-- /NOTE/: Not all data may be flushed in a single call; the encoder must be
-- invoked repeatedly with this parameter, until it returns @0@.
-- 
-- /NOTE/: Multi-threaded compression will block to flush as much output as
-- possible.
zstd_e_flush :: CInt
zstd_e_flush = #const ZSTD_e_flush

-- | @ZSTD_e_end@ streaming compression parameter, indicates that the encoder
-- should flush any buffered data before closing the frame with an epilogue.
--
-- The frame will not continue and any subsequent input starts a new frame,
-- which cannot reference previously compressed data.
--
-- /NOTE/: Not all data may be drained in a single call; the encoder must be
-- invoked repeatedly with this parameter, until it returns @0@.
--
-- /NOTE/: Multi-threaded compression will block to drain as much output as
-- possible.
zstd_e_end :: CInt
zstd_e_end = #const ZSTD_e_end

-- | @ZSTD_reset_session_only@ reset directive, resets session state and
-- preserves parameter values.
zstd_reset_session_only :: CInt
zstd_reset_session_only = #const ZSTD_reset_session_only

-- | @ZSTD_reset_parameters@ reset directive, resets parameter values.
--
-- /NOTE/: Only valid before a session begins.
zstd_reset_parameters :: CInt
zstd_reset_parameters = #const ZSTD_reset_parameters

-- | @ZSTD_reset_session_and_parameters@ reset directive, resets both session
-- state and parameter values.
zstd_reset_session_and_parameters :: CInt
zstd_reset_session_and_parameters = #const ZSTD_reset_session_and_parameters
