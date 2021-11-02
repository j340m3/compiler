module Stage.Emit.Python exposing
    ( emitProject
    , emitDeclaration, emitExpr
    )

{-| The `emitProject` function is the main entrypoint in this module, ie. every
`Stage.Emit.<INSERT LANGUAGE HERE>` module has to expose this function to fit
well with the APIs of the other stages. See src/cli/Main.elm and its `compile`
function for example usage.

@docs emitProject

All the other exposed functions are (as of time of writing) exposed only for
testing purposes.

@docs emitDeclaration, emitExpr

-}

import Dict exposing (Dict)
import Elm.AST.Typed as Typed exposing (Expr_(..))
import Elm.Compiler.Error exposing (Error)
import Elm.Data.Declaration exposing (Declaration, DeclarationBody(..))
import Elm.Data.FileContents exposing (FileContents)
import Elm.Data.FilePath exposing (FilePath)
import Elm.Data.Located as Located
import Elm.Data.ModuleName exposing (ModuleName)
import Elm.Data.Project exposing (Project)
import Elm.Data.Qualifiedness exposing (Qualified)
import Elm.Data.Type as Type
import Elm.Data.VarName exposing (VarName)
import Stage.Emit.Common exposing (prepareProjectFields)


type alias ProjectFields =
    { declarationList : List (Declaration Typed.LocatedExpr Never Qualified) }


emitExpr : Typed.LocatedExpr -> String
emitExpr located =
    case Typed.getExpr located of
        Int int ->
            -- TODO think about NaNs / infinities
            String.fromInt int

        Float float ->
            -- TODO think about NaNs / infinities
            String.fromFloat float

        Char char ->
            -- TODO escaping
            "'" ++ String.fromChar char ++ "'"

        String string ->
            -- TODO escaping
            "\"" ++ string ++ "\""

        Bool bool ->
            if bool then
                "True"

            else
                "False"

        Var var ->
            mangleQualifiedVar var

        Argument argument ->
            mangleVarName argument

        Plus e1 e2 ->
            "("
                ++ emitExpr e1
                ++ " + "
                ++ emitExpr e2
                ++ ")"

        Cons e1 e2 ->
            -- [x, *xs]
            -- [1, *[2,3,4]]
            "["
                ++ emitExpr e1
                ++ ", *("
                ++ emitExpr e2
                ++ ")]"

        Lambda { argument, body } ->
            "(lambda "
                ++ mangleVarName argument
                ++ ": "
                ++ emitExpr body
                ++ ")"

        Call { fn, argument } ->
            -- TODO are these parentheses needed?
            "("
                ++ emitExpr fn
                ++ "("
                ++ emitExpr argument
                ++ "))"

        If { test, then_, else_ } ->
            "("
                ++ emitExpr then_
                ++ " if "
                ++ emitExpr test
                ++ " else "
                ++ emitExpr else_
                ++ ")"

        Let { bindings, body } ->
            bindings
                |> Dict.values
                {- TODO this doesn't take inter-let dependencies into
                   account, also Dict.values just returns stuff "randomly"
                -}
                |> List.foldl
                    (\binding acc ->
                        "(lambda "
                            ++ mangleVarName binding.name
                            ++ ": "
                            ++ acc
                            ++ ")("
                            ++ emitExpr binding.body
                            ++ ")"
                    )
                    (emitExpr body)

        List items ->
            "["
                ++ (List.map emitExpr items |> String.join ", ")
                ++ "]"

        Unit ->
            "None"

        Tuple e1 e2 ->
            "("
                ++ emitExpr e1
                ++ ","
                ++ emitExpr e2
                ++ ")"

        Tuple3 e1 e2 e3 ->
            "("
                ++ emitExpr e1
                ++ ","
                ++ emitExpr e2
                ++ ","
                ++ emitExpr e3
                ++ ")"

        Record bindings ->
            let
                bindingsPython =
                    bindings
                        |> Dict.values
                        |> List.map
                            (\binding ->
                                "'"
                                    ++ mangleVarName binding.name
                                    ++ "': "
                                    ++ emitExpr binding.body
                            )
                        |> String.join ", "
            in
            "{" ++ bindingsPython ++ "}"

        Case _ _ ->
            "TODO"

        ConstructorValue _ ->
            "TODO"


mangleQualifiedVar : { module_ : ModuleName, name : VarName } -> String
mangleQualifiedVar { module_, name } =
    mangleModuleName module_ ++ "___" ++ mangleVarName name


mangleModuleName : ModuleName -> String
mangleModuleName moduleName =
    String.replace "." "__" moduleName


mangleVarName : VarName -> String
mangleVarName varName =
    -- TODO this does nothing currently...
    varName


emitDeclaration : Declaration Typed.LocatedExpr Never Qualified -> String
emitDeclaration { module_, name, body } =
    case body of
        Value { expression } ->
            mangleQualifiedVar { module_ = module_, name = name }
                ++ " = "
                ++ emitExpr expression

        TypeAlias _ ->
            ""

        CustomType _ ->
            ""

        Port _ ->
            -- TODO somehow emit ports!
            ""


emitMainCall : List (Declaration Typed.LocatedExpr Never Qualified) -> String -> String
emitMainCall declarationList fileString =
    if List.any (\{ module_, name } -> module_ == "Main" && name == "main") declarationList then
        fileString ++ "\n\nif __name__ == \"__main__\":\n\tMain___main()"

    else
        fileString


emitProject : Project Typed.ProjectFields -> Result Error (Dict FilePath FileContents)
emitProject project =
    Ok project
        |> Result.andThen prepareProjectFields
        |> Result.map emitProject_


emitProject_ : Project ProjectFields -> Dict FilePath FileContents
emitProject_ { declarationList } =
    declarationList
        |> List.map emitDeclaration
        |> String.join "\n"
        |> emitMainCall declarationList
        |> Dict.singleton "out.py"
