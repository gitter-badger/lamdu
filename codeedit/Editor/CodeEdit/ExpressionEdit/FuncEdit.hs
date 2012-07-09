module Editor.CodeEdit.ExpressionEdit.FuncEdit(make, makeParamEdit) where

import Control.Arrow (second)
import Control.Monad (liftM, (<=<))
import Data.List.Utils (pairList)
import Data.Monoid (mempty, mconcat)
import Data.Store.Guid (Guid)
import Editor.Anchors (ViewTag)
import Editor.CodeEdit.ExpressionEdit.ExpressionGui (ExpressionGui(..))
import Editor.MonadF (MonadF)
import Editor.OTransaction (OTransaction, TWidget, WidgetT)
import qualified Data.List as List
import qualified Editor.BottleWidgets as BWidgets
import qualified Editor.CodeEdit.ExpressionEdit.ExpressionGui as ExpressionGui
import qualified Editor.CodeEdit.Sugar as Sugar
import qualified Editor.Config as Config
import qualified Editor.ITransaction as IT
import qualified Editor.OTransaction as OT
import qualified Editor.WidgetIds as WidgetIds
import qualified Graphics.UI.Bottle.EventMap as E
import qualified Graphics.UI.Bottle.Widget as Widget
import qualified Graphics.UI.Bottle.Widgets.FocusDelegator as FocusDelegator

paramFDConfig :: FocusDelegator.Config
paramFDConfig = FocusDelegator.Config
  { FocusDelegator.startDelegatingKey = E.ModKey E.noMods E.KeyEnter
  , FocusDelegator.startDelegatingDoc = "Change parameter name"
  , FocusDelegator.stopDelegatingKey = E.ModKey E.noMods E.KeyEsc
  , FocusDelegator.stopDelegatingDoc = "Stop changing name"
  }

makeParamNameEdit
  :: MonadF m
  => Guid
  -> TWidget t m
makeParamNameEdit ident =
  BWidgets.wrapDelegated paramFDConfig FocusDelegator.NotDelegating id
  (BWidgets.setTextColor Config.parameterColor .
   BWidgets.makeNameEdit "<unnamed param>" ident) $
  WidgetIds.paramId ident

both :: (a -> b) -> (a, a) -> (b, b)
both f (x, y) = (f x, f y)

-- exported for use in definition sugaring.
makeParamEdit
  :: MonadF m
  => ExpressionGui.Maker m
  -> Sugar.FuncParam m
  -> OTransaction ViewTag m (WidgetT ViewTag m, WidgetT ViewTag m)
makeParamEdit makeExpressionEdit param =
  OT.assignCursor (WidgetIds.fromGuid ident) (WidgetIds.paramId ident) .
    (liftM . both . Widget.weakerEvents) paramEventMap $ do
    paramNameEdit <- makeParamNameEdit ident
    paramTypeEdit <- makeExpressionEdit $ Sugar.fpType param
    return
      (-- TODO: Widget.align down
       paramNameEdit,
       -- TODO: Widget.align up
       ExpressionGui.egWidget paramTypeEdit)
  where
    ident = Sugar.guid $ Sugar.fpEntity param
    -- up = Vector2 0.5 0
    -- down = Vector2 0.5 1
    paramEventMap = mconcat
      [ paramDeleteEventMap
      , paramAddNextEventMap
      ]
    paramAddNextEventMap =
      maybe mempty
      (Widget.keysEventMapMovesCursor Config.addNextParamKeys "Add next parameter" .
       liftM (FocusDelegator.delegatingId . WidgetIds.paramId) .
       IT.transaction . Sugar.lambdaWrap) .
      Sugar.eActions . Sugar.rEntity $
      Sugar.fpBody param
    paramDeleteEventMap =
      maybe mempty
      (Widget.keysEventMapMovesCursor Config.delKeys "Delete parameter" .
       liftM WidgetIds.fromGuid .
       IT.transaction) .
      (Sugar.mDelete <=< Sugar.eActions) $ Sugar.fpEntity param

makeParamsEdit
  :: MonadF m
  => ExpressionGui.Maker m
  -> [Sugar.FuncParam m]
  -> OTransaction ViewTag m (ExpressionGui m)
makeParamsEdit makeExpressionEdit =
  liftM
  (ExpressionGui . BWidgets.gridHSpacedCentered . List.transpose .
   map (pairList . scaleDownType)) .
  mapM (makeParamEdit makeExpressionEdit)
  where
    scaleDownType = second $ Widget.scale Config.typeScaleFactor

make
  :: MonadF m
  => ExpressionGui.Maker m
  -> Sugar.Func m
  -> Widget.Id
  -> OTransaction ViewTag m (ExpressionGui m)
make makeExpressionEdit (Sugar.Func params body) myId =
  OT.assignCursor myId ((WidgetIds.fromGuid . Sugar.guid . Sugar.rEntity) body) $ do
    lambdaLabel <-
      liftM ExpressionGui .
      OT.setTextSizeColor Config.lambdaTextSize Config.lambdaColor .
      BWidgets.makeLabel "λ" $ Widget.toAnimId myId
    rightArrowLabel <-
      liftM ExpressionGui .
      OT.setTextSizeColor Config.rightArrowTextSize Config.rightArrowColor .
      BWidgets.makeLabel "→" $ Widget.toAnimId myId
    bodyEdit <- makeExpressionEdit body
    paramsEdit <- makeParamsEdit makeExpressionEdit params
    return $ ExpressionGui.hboxSpaced [lambdaLabel, paramsEdit, rightArrowLabel, bodyEdit]
