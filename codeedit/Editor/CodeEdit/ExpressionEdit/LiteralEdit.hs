{-# LANGUAGE OverloadedStrings #-}

module Editor.CodeEdit.ExpressionEdit.LiteralEdit(makeInt, makeIntView) where

import Control.Monad (liftM)
import Data.Store.Transaction (Transaction)
import Editor.Anchors(ViewTag)
import Editor.CodeEdit.ExpressionEdit.ExpressionGui (ExpressionGui(..))
import Editor.MonadF(MonadF)
import Editor.OTransaction (OTransaction)
import Graphics.UI.Bottle.Animation (AnimId)
import qualified Data.Char as Char
import qualified Editor.BottleWidgets as BWidgets
import qualified Editor.CodeEdit.ExpressionEdit.ExpressionGui as ExpressionGui
import qualified Editor.CodeEdit.Sugar as Sugar
import qualified Editor.Config as Config
import qualified Editor.ITransaction as IT
import qualified Editor.OTransaction as OT
import qualified Graphics.UI.Bottle.EventMap as E
import qualified Graphics.UI.Bottle.Widget as Widget
import qualified Graphics.UI.Bottle.Widgets.FocusDelegator as FocusDelegator
import qualified Graphics.UI.Bottle.Widgets.TextEdit as TextEdit

setColor :: OTransaction t m a -> OTransaction t m a
setColor = BWidgets.setTextColor Config.literalIntColor

makeIntView
  :: Monad m
  => AnimId -> Integer
  -> OTransaction ViewTag m (ExpressionGui m)
makeIntView myId integer =
  liftM ExpressionGui .
  setColor $ BWidgets.makeTextView (show integer) myId

makeIntEdit
  :: Monad m
  => Sugar.LiteralInteger m -> Widget.Id
  -> OTransaction ViewTag m (ExpressionGui m)
makeIntEdit integer myId =
  case Sugar.liSetValue integer of
    Nothing -> makeIntView (Widget.toAnimId myId) (Sugar.liValue integer)
    Just setValue -> makeIntEditI integer myId setValue

makeIntEditI
  :: Monad m
  => Sugar.LiteralInteger m -> Widget.Id
  -> (Integer -> Transaction ViewTag m ())
  -> OTransaction ViewTag m (ExpressionGui m)
makeIntEditI integer myId setValue = do
  cursor <- OT.readCursor
  suffix <- OT.subCursor myId
  let
    isEmpty = Sugar.liValue integer == 0 && suffix == Just emptyZeroCursor
    (text, textCursor)
      | isEmpty = ("", TextEdit.makeTextEditCursor myId 0)
      | otherwise = (show (Sugar.liValue integer), cursor)
    setter (newText, eventRes)
      | newText == text = return eventRes
      | not (all Char.isDigit newText) = return Widget.emptyEventResult
      | null newText = do
        _ <- IT.transaction $ setValue 0
        return . Widget.eventResultFromCursor $ Widget.joinId myId emptyZeroCursor
      | otherwise = do
        _ <- IT.transaction $ setValue $ read newText
        return eventRes
  style <- OT.readTextStyle
  return .
    ExpressionGui .
    Widget.atEvents setter .
    Widget.atWEventMap removeKeys $ TextEdit.make
    style { TextEdit.sEmptyFocusedString = "<0>" } textCursor text myId
  where
    removeKeys =
      E.filterChars Char.isDigit .
      foldr (.) id
      [ E.deleteKey (E.KeyEvent E.Press (E.ModKey E.noMods key))
      | key <- [E.KeyEnter, E.KeySpace]
      ]
    emptyZeroCursor = ["empty-zero"]

literalFDConfig :: FocusDelegator.Config
literalFDConfig = FocusDelegator.Config
  { FocusDelegator.startDelegatingKey = E.ModKey E.noMods E.KeyEnter
  , FocusDelegator.startDelegatingDoc = "Change integer"
  , FocusDelegator.stopDelegatingKey = E.ModKey E.noMods E.KeyEsc
  , FocusDelegator.stopDelegatingDoc = "Stop changing integer"
  }

makeInt
  :: MonadF m
  => Sugar.LiteralInteger m
  -> Widget.Id
  -> OTransaction ViewTag m (ExpressionGui m)
makeInt integer =
  BWidgets.wrapDelegated literalFDConfig FocusDelegator.NotDelegating ExpressionGui.atEgWidget
  (setColor . makeIntEdit integer)
