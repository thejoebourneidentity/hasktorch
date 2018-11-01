    let prelude = ../../dhall/dhall-to-cabal/dhall/prelude.dhall
in  let types =   ../../dhall/dhall-to-cabal/dhall/types.dhall
in  let common = ../../dhall/common.dhall
in  let packages = common.packages
in  common.Package
   // { name = "hasktorch-signatures-support"
      , synopsis = "Signatures for support tensors in hasktorch"
      , description = "Backpack signatures which define redundant operators for mask tensors and index tensors in Hasktorch."
      , library =
          [   λ(config : types.Config)
            →   common.Library
              // { hs-source-dirs = [ "src" ]
                 , build-depends =
                    [ packages.base
                    , packages.hasktorch-signatures-types
                    , packages.hasktorch-types-th
                    ]
                 , signatures =
                   [ "Torch.Sig.Index.Tensor"
                   , "Torch.Sig.Index.TensorFree"
                   , "Torch.Sig.Mask.Tensor"
                   , "Torch.Sig.Mask.TensorFree"
                   , "Torch.Sig.Mask.MathReduce"
                   ]
                }
          ] : Optional (types.Config → types.Library)
      }
