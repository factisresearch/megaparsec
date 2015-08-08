-- |
-- Module      :  Text.Megaparsec.Error
-- Copyright   :  © 2015 Megaparsec contributors
--                © 2007 Paolo Martini
--                © 1999–2001 Daan Leijen
-- License     :  BSD3
--
-- Maintainer  :  Mark Karpov <markkarpov@opmbx.org>
-- Stability   :  experimental
-- Portability :  portable
--
-- Parse errors.

module Text.Megaparsec.Error
    ( Message (SysUnExpect, UnExpect, Expect, Message)
    , messageString
    , ParseError
    , errorPos
    , errorMessages
    , errorIsUnknown
    , newErrorMessage
    , newErrorUnknown
    , addErrorMessage
    , setErrorMessage
    , setErrorPos
    , mergeError
    , showMessages )
where

import Data.List (sort, intercalate)

import Text.Megaparsec.Pos

-- | This abstract data type represents parse error messages. There are
-- four kinds of messages:
--
-- > data Message = SysUnExpect String
-- >              | UnExpect    String
-- >              | Expect      String
-- >              | Message     String
--
-- The fine distinction between different kinds of parse errors allows the
-- system to generate quite good error messages for the user. It also allows
-- error messages that are formatted in different languages. Each kind of
-- message is generated by different combinators:
--
--     * A 'SysUnExpect' message is automatically generated by the
--       'Text.Parsec.Combinator.satisfy' combinator. The argument is the
--       unexpected input.
--
--     * A 'UnExpect' message is generated by the
--       'Text.Parsec.Prim.unexpected' combinator. The argument describes
--       the unexpected item.
--
--     * A 'Expect' message is generated by the 'Text.Parsec.Prim.<?>'
--       combinator. The argument describes the expected item.
--
--     * A 'Message' message is generated by the 'fail' combinator. The
--       argument is some general parser message.

data Message = SysUnExpect !String -- @ library generated unexpect
             | UnExpect    !String -- @ unexpected something
             | Expect      !String -- @ expecting something
             | Message     !String -- @ raw message
               deriving Show

instance Enum Message where
    fromEnum (SysUnExpect _) = 0
    fromEnum (UnExpect    _) = 1
    fromEnum (Expect      _) = 2
    fromEnum (Message     _) = 3
    toEnum _ = error "Text.Megaparsec.Error: toEnum is undefined for Message"

instance Eq Message where
    m1 == m2 =
        fromEnum m1 == fromEnum m2 && messageString m1 == messageString m2

instance Ord Message where
    compare m1 m2 =
        case compare (fromEnum m1) (fromEnum m2) of
          LT -> LT
          EQ -> compare (messageString m1) (messageString m2)
          GT -> GT

-- | Extract the message string from an error message

messageString :: Message -> String
messageString (SysUnExpect s) = s
messageString (UnExpect    s) = s
messageString (Expect      s) = s
messageString (Message     s) = s

-- | The abstract data type @ParseError@ represents parse errors. It
-- provides the source position ('SourcePos') of the error and a list of
-- error messages ('Message'). A @ParseError@ can be returned by the
-- function 'Text.Parsec.Prim.parse'. @ParseError@ is an instance of the
-- 'Show' and 'Eq' classes.

data ParseError = ParseError
    { -- | Extract the source position from the parse error.
      errorPos :: !SourcePos
      -- | Extract the list of error messages from the parse error.
    , errorMessages :: [Message] }

instance Show ParseError where
    show e = show (errorPos e) ++ ":\n" ++ showMessages (errorMessages e)

instance Eq ParseError where
    l == r =
        errorPos l == errorPos r && errorMessages l == errorMessages r

-- | Test whether given @ParseError@ has associated collection of error
-- messages. Return @True@ if it has none and @False@ otherwise.

errorIsUnknown :: ParseError -> Bool
errorIsUnknown (ParseError _ ms) = null ms

-- Creation of parse errors

-- | @newErrorUnknown pos@ creates @ParseError@ without any associated
-- message but with specified position @pos@.

newErrorUnknown :: SourcePos -> ParseError
newErrorUnknown pos = ParseError pos []

-- | @newErrorMessage m pos@ creates @ParseError@ with message @m@ and
-- associated position @pos@.

newErrorMessage :: Message -> SourcePos -> ParseError
newErrorMessage m pos = ParseError pos [m]

-- | @addErrorMessage m err@ returns @ParseError@ @err@ with message @m@
-- added. This function makes sure that list of messages is always ordered
-- and doesn't contain duplicates.

addErrorMessage :: Message -> ParseError -> ParseError
addErrorMessage m (ParseError pos ms) = ParseError pos (pre ++ [m] ++ post)
    where pre  = filter (< m) ms
          post = filter (> m) ms

-- | @setErrorMessage m err@ returns @err@ with message @m@ added. This
-- function also deletes all existing error messages that were created with
-- the same constructor as @m@.

setErrorMessage :: Message -> ParseError -> ParseError
setErrorMessage m (ParseError pos ms) = addErrorMessage m (ParseError pos xs)
    where xs = filter ((/= fromEnum m) . fromEnum) ms

-- | @setErrorPos pos err@ returns @ParseError@ identical to @err@, but with
-- position @pos@.

setErrorPos :: SourcePos -> ParseError -> ParseError
setErrorPos pos (ParseError _ ms) = ParseError pos ms

-- | Merge two error data structures into one joining their collections of
-- messages and preferring shortest match.

mergeError :: ParseError -> ParseError -> ParseError
mergeError e1@(ParseError pos1 ms1) e2@(ParseError pos2 ms2) =
    case pos1 `compare` pos2 of
      LT -> e1
      EQ -> ParseError pos1 (sort $ ms1 ++ ms2)
      GT -> e2

-- | @showMessages ms@ transforms list of error messages @ms@ into
-- their textual representation.

showMessages :: [Message] -> String
showMessages [] = "unknown parse error"
showMessages ms =
    intercalate "\n" $ clean [sysUnExpect', unExpect', expect', msgs']
    where
      (sysUnExpect, ms1) = span ((== 0) . fromEnum) ms
      (unExpect,    ms2) = span ((== 1) . fromEnum) ms1
      (expect, messages) = span ((== 2) . fromEnum) ms2

      sysUnExpect'
          | not (null unExpect) || null sysUnExpect = ""
          | otherwise = showMany "unexpected " (emptyToEnd <$> sysUnExpect)
      unExpect' = showMany "unexpected " unExpect
      expect'   = showMany "expecting "  expect
      msgs'     = showMany "" messages

      emptyToEnd (SysUnExpect x) =
          SysUnExpect $ if null x then "end of input" else x
      emptyToEnd x = x

      showMany pre msgs =
          case clean (messageString <$> msgs) of
            [] -> ""
            xs | null pre  -> commasOr xs
               | otherwise -> pre ++ commasOr xs

      commasOr []  = ""
      commasOr [x] = x
      commasOr xs  = intercalate ", " (init xs) ++ " or " ++ last xs

      clean = filter (not . null)
