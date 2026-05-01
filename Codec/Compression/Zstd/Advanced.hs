-- Copyright (c) 2016-present, Facebook, Inc.
-- All rights reserved.
--
-- This source code is licensed under the BSD-style license found in
-- the LICENSE file in the root directory of this source tree. An
-- additional grant of patent rights can be found in the PATENTS file
-- in the same directory.

-- |
-- Module      : Codec.Compression.Zstd.Advanced
-- Copyright   : (c) 2016-present, Facebook, Inc. All rights reserved.
--
-- License     : BSD3
-- Maintainer  : luis@luispedro.org
-- Stability   : experimental
-- Portability : GHC
--
-- Partial coverage for zstd's advanced API.
--
-- Meant to be used alongside 'Codec.Compression.Zstd.Efficient' to support
-- advanced library features, such as parallel compression.

module Codec.Compression.Zstd.Advanced
    (
      CParameter(..)
    , setCParameter
    , ResetMode(..)
    , resetCCtx
    , compress2CCtx
    , hasMultithreadedSupport
    ) where

import qualified Codec.Compression.Zstd.FFI as C
import Codec.Compression.Zstd.Internal
import Control.Monad (when)
import Data.ByteString (ByteString)
import System.IO.Unsafe (unsafePerformIO)

-- | A compression parameter that can be set on a 'CCtx' via
-- 'setCParameter'.
--
-- Parameters are "sticky": once set, they apply to all subsequent
-- 'compress2CCtx' calls until 'resetCCtx' clears them.
data CParameter
    = CompressionLevel Int
      -- ^ @ZSTD_c_compressionLevel@
      --
      -- Default @3@, must be between @1..'C.maxCLevel'@.
    | NbWorkers Int
      -- ^ @ZSTD_c_nbWorkers@
      --
      -- @0@ disables threading; @>= 1@ runs that many worker threads.
      --
      -- /NOTE/: If the linked @libzstd@ was built without support for
      -- multi-threading support, any non-zero call will fail; call
      -- 'checkMultithreadedSupport' first if unsure.
    | JobSize Int
      -- ^ @ZSTD_c_jobSize@.
      --
      -- Size, in bytes, of one compression job in multi-threaded mode.
      --
      -- @0@ requests an automatic value.
    | OverlapLog Int
      -- ^ @ZSTD_c_overlapLog@.
      --
      -- Overlap of consecutive jobs in multi-threaded mode.
      --
      -- @0@ = no overlap; @9@ = full window.
    deriving (Eq, Show)

-- | Set a compression parameter on the context; parameters are sticky
-- across 'compress2CCtx' calls.
--
-- Raises an error if the parameter is invalid for the linked @libzstd@ version.
setCParameter :: CCtx -> CParameter -> IO ()
setCParameter (CCtx cc) p = do
    let (param, value) = encode p
    rc <- C.cCtxSetParameter cc param (fromIntegral value)
    when (C.isError rc) $
      error $ "Codec.Compression.Zstd.Advanced.setCParameter: " ++ C.getErrorName rc
  where
    encode (CompressionLevel n) = (C.zstd_c_compressionLevel, n)
    encode (NbWorkers n)        = (C.zstd_c_nbWorkers,        n)
    encode (JobSize n)          = (C.zstd_c_jobSize,          n)
    encode (OverlapLog n)       = (C.zstd_c_overlapLog,       n)

-- | A reset directive, which determines what to clear when calling 'resetCCtx'.
data ResetMode
    = ResetSession
      -- ^ Reset session state (buffered input/output, partial frame).
    | ResetParameters
      -- ^ Reset parameters to defaults.
      --
      -- /NOTE/: Only valid before a session starts (i.e. before the first
      -- compress call after a reset).
    | ResetBoth
      -- ^ Reset both session state and parameters.
    deriving (Eq, Show)

-- | Reset a 'CCtx'.
resetCCtx :: CCtx -> ResetMode -> IO ()
resetCCtx (CCtx cc) mode = do
    rc <- C.cCtxReset cc (encode mode)
    if C.isError rc
      then error ("Codec.Compression.Zstd.Advanced.resetCCtx: " ++
                  C.getErrorName rc)
      else pure ()
  where
    encode ResetSession    = C.zstd_reset_session_only
    encode ResetParameters = C.zstd_reset_parameters
    encode ResetBoth       = C.zstd_reset_session_and_parameters

-- | Compress using the advanced API: any sticky parameters set via
-- 'setCParameter' (compression level, worker threads, etc.) are honored.
--
-- Always starts a new frame; any partial frame state on the context is
-- discarded.
compress2CCtx :: CCtx
              -- ^ Compression context.
              -> ByteString
              -- ^ Payload to compress.
              -> IO ByteString
compress2CCtx (CCtx cc) bs =
    compress2With "compress2CCtx" (C.c_compress2 cc) bs

-- | 'True' if @libzstd@ was compiled with multi-threading
-- support.
--
-- If 'False', any 'NbWorkers' value @>= 1@ passed to 'setCParameter' will fail.
hasMultithreadedSupport :: Bool
hasMultithreadedSupport = unsafePerformIO $ withCCtx $ \(CCtx cc) ->
    not . C.isError <$> C.cCtxSetParameter cc C.zstd_c_nbWorkers 1
{-# NOINLINE hasMultithreadedSupport #-}
