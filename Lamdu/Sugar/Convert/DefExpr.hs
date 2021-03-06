{-# LANGUAGE NoImplicitPrelude, OverloadedStrings, ScopedTypeVariables #-}
module Lamdu.Sugar.Convert.DefExpr
    ( convert
    ) where

import           Prelude.Compat

import qualified Control.Lens as Lens
import           Control.Lens.Operators
import           Control.Lens.Tuple
import           Control.Monad.Trans.Either (runEitherT)
import           Control.MonadA (MonadA)
import           Data.CurAndPrev (CurAndPrev(..))
import           Data.Store.Guid (Guid)
import qualified Data.Store.IRef as IRef
import qualified Data.Store.Property as Property
import           Data.Store.Transaction (Transaction)
import qualified Data.Store.Transaction as Transaction
import           Lamdu.Builtins.Anchors (recurseVar)
import qualified Lamdu.Data.Anchors as Anchors
import qualified Lamdu.Data.Definition as Definition
import           Lamdu.Eval.Results (EvalResults, erExprValues, erAppliesOfLam)
import           Lamdu.Expr.IRef (DefI)
import qualified Lamdu.Expr.IRef as ExprIRef
import qualified Lamdu.Expr.IRef.Infer as IRefInfer
import           Lamdu.Expr.Scheme (Scheme(..))
import qualified Lamdu.Expr.Scheme as Scheme
import           Lamdu.Expr.Val (Val(..))
import qualified Lamdu.Expr.Val as V
import qualified Lamdu.Infer as Infer
import qualified Lamdu.Sugar.Convert.Binder as ConvertBinder
import qualified Lamdu.Sugar.Convert.Expression as ConvertExpr
import qualified Lamdu.Sugar.Convert.Input as Input
import           Lamdu.Sugar.Convert.Monad (Context(..))
import qualified Lamdu.Sugar.Convert.Monad as ConvertM
import qualified Lamdu.Sugar.Convert.ParamList as ParamList
import           Lamdu.Sugar.Internal
import qualified Lamdu.Sugar.Internal.EntityId as EntityId
import           Lamdu.Sugar.Types
import           Text.PrettyPrint.HughesPJClass (pPrint)

type T = Transaction

mkContext ::
    MonadA m =>
    DefI m -> Anchors.Code (Transaction.MkProperty m) m -> Infer.Context ->
    Context m
mkContext defI cp inferContext =
    Context
    { _scInferContext = inferContext
    , _scDefI = defI
    , _scCodeAnchors = cp
    , _scTagParamInfos = mempty
    , _scMExtractDestPos = Nothing
    , _scNullParams = mempty
    , _scReinferCheckDefinition =
          do
              defBody <- Transaction.readIRef defI
              case defBody of
                  Definition.BodyBuiltin {} -> return True
                  Definition.BodyExpr (Definition.Expr valI _) ->
                      ExprIRef.readVal valI
                      <&> fmap (flip (,) ())
                      <&> ExprIRef.addProperties (error "TODO: DefExpr root setIRef")
                      <&> fmap fst
                      >>= -- TODO: loadInfer is for sugar, we don't need sugar here
                          loadInfer mempty
                      <&> Lens.has Lens._Right
    , scConvertSubexpression = ConvertExpr.convert
    }

makeExprDefTypeInfo ::
    MonadA m => ExprIRef.ValI m -> DefI m -> Definition.ExportedType -> Scheme -> DefinitionTypeInfo m
makeExprDefTypeInfo _ _ (Definition.ExportedType defType) inferredType
    | defType `Scheme.alphaEq` inferredType = DefinitionExportedTypeInfo defType
makeExprDefTypeInfo defValI defI defType inferredType =
    DefinitionNewType AcceptNewType
    { antOldExportedType = defType
    , antNewInferredType = inferredType
    , antAccept =
        Transaction.writeIRef defI $
        Definition.BodyExpr $
        Definition.Expr defValI $ Definition.ExportedType inferredType
    }

loadInfer ::
    MonadA m =>
    CurAndPrev (EvalResults (ExprIRef.ValI m)) ->
    Val (ExprIRef.ValIProperty m) ->
    T m (Either IRefInfer.Error (Val (Input.Payload m ()), Infer.Context))
loadInfer evalRes val =
    IRefInfer.loadInfer recurseVar val
    <&> _1 . Lens.mapped %~ mkPayload
    >>= ParamList.loadForLambdas
    & runEitherT
    where
        mkPayload (inferPl, valIProp) =
            Input.mkPayload () inferPl
            (evalRes <&> exprEvalRes execId)
            valIProp
            where
                execId = Property.value valIProp
        exprEvalRes pl r =
            Input.EvalResultsForExpr
            (r ^. erExprValues . Lens.at pl . Lens._Just)
            (r ^. erAppliesOfLam . Lens.at pl . Lens._Just)

convert ::
    MonadA m =>
    CurAndPrev (EvalResults (ExprIRef.ValI m)) ->
    Anchors.CodeProps m ->
    Definition.Expr (Val (ExprIRef.ValIProperty m)) ->
    DefI m -> T m (DefinitionBody Guid m (ExpressionU m [EntityId]))
convert evalRes cp (Definition.Expr val defType) defI =
    do
        (valInferred, newInferContext) <-
            loadInfer evalRes val
            <&> either (error . ("Type inference failed: " ++) . show . pPrint) id
        content <-
            valInferred <&> addStoredEntityIds
            & ConvertBinder.convertBinder (Just recurseVar) defGuid
            & ConvertM.run (mkContext defI cp newInferContext)
        return $ DefinitionBodyExpression DefinitionExpression
            { _deContent = content
            , _deTypeInfo =
                makeExprDefTypeInfo exprI defI defType $
                Infer.makeScheme newInferContext $
                valInferred ^. V.payload . Input.inferredType
            }
    where
        addStoredEntityIds x =
            x
            & Input.userData .~
                (x ^.. Input.mStored . Lens._Just
                  <&> EntityId.ofValI . Property.value)
        exprI = val ^. V.payload . Property.pVal
        defGuid = IRef.guid defI
