-- |
-- Module      : Codec.Compression.Zstd.Parallel
-- License     : BSD3
-- Stability   : experimental
-- Portability : GHC
--
-- High-level helpers for compression with multiple worker threads.
--
-- For best results, prefer parallel compression for inputs above ~256 KiB
-- and at compression levels >= 3. For small inputs, the synchronization
-- overhead of dispatching jobs to worker threads can outweigh any speedup.
--
-- /NOTE/: Multi-threading support depends on how the linked @libzstd@ was
-- built; 'hasMultithreadedSupport' returns 'True' if the runtime library
-- supports it.

module Codec.Compression.Zstd.Parallel
    (
      -- * Basic pure API
      compress
    , hasMultithreadedSupport
    ) where

import Codec.Compression.Zstd.Advanced
    ( CParameter(..)
    , compress2CCtx
    , hasMultithreadedSupport
    , setCParameter
    )
import Codec.Compression.Zstd.Internal (withCCtx)
import Data.ByteString (ByteString)
import System.IO.Unsafe (unsafePerformIO)

-- | Compress the given data as a single zstd compressed frame with optional
-- parallelism.
--
-- /NOTE/: Raises an 'error' call if one or more workers was requested, but the
-- linked @libzstd@ was built without multi-threading support; consult
-- 'hasMultithreadedSupport' ahead of time to confirm the build configuration.
--
-- /NOTE/: Raises an 'error' call if the given compression level is invalid.
-- 
-- /NOTE/: Parallelism is handled entirely by @libzstd@, /not/ by GHC's
-- runtime; workers allocate OS threads, /not/ Haskell's green threads.
compress :: Int
         -- ^ Number of worker threads. @0@ disables threading.
         -> Int
         -- ^ Compression level. Must be @>= 1@ and @<=
         -- 'Codec.Compression.Zstd.maxCLevel'@.
         -> ByteString
         -- ^ Payload to compress.
         -> ByteString
compress workers level bs = unsafePerformIO $ withCCtx $ \ctx -> do
    setCParameter ctx (CompressionLevel level)
    setCParameter ctx (NbWorkers workers)
    compress2CCtx ctx bs
