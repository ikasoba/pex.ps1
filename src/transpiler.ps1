using namespace System.Management.Automation.Language
using namespace System.Collections.Generic

class Transpiler: ICustomAstVisitor {
  Transpiler(): base() {}

  [string]ConvertFuncName([string]$name){
    if ($name -eq "Write-Host"){
      return "console.log"
    }elseif ($name -eq "Write-Error"){
      return "console.error"
    }elseif ($name -eq "Write-Output"){
      return "`$`$__output__.add"
    }else{
      return $this.ConvertIdent($name)
    }
  }

  [string]ConvertIdent([string]$ident){
    return $ident -replace "-", "_" -replace ":", "_"
  }

  [object]VisitArrayExpression([ArrayExpressionAst]$arr){
    return "[$(
      [string]::Join(", ", (
        $arr.SubExpression.Statements | ForEach-Object {
          $_.Visit($this)
        }
      ))
    )].flat(-1)"
  }

  [object]VisitArrayLiteral([ArrayLiteralAst]$arr){
    return "[$(
      [string]::Join(", ", (
        $arr.Elements | ForEach-Object {
          $_.Visit($this)
        }
      ))
    )]"
  }

  [object]VisitScriptBlock([ScriptBlockAst]$scriptblock){
    Write-Host $scriptblock.ParamBlock
    return "((_, $(
      (
        ($null -ne $scriptblock.ParamBlock.Parameters) ? ($scriptblock.ParamBlock.Parameters | ForEach-Object { $_.Visit($this) }) : @()
      ) -Join ", "
    )) => {const `$`$__output__ = {add(...values){ this.data.push(...values.filter(x => x !== undefined)) }, data: []}; " + $scriptblock.EndBlock.Visit($this) + " ;return `$`$__output__.data})"
  }

  [object]VisitNamedBlock([NamedBlockAst]$block){
    return ($block.Statements | ForEach-Object {
      $_.Visit($this)
    }) -Join "`n"
  }

  [object]VisitPipeline([PipelineAst]$pipeline){
    if ($pipeline.PipelineElements.Count -eq 1){
      return $pipeline.PipelineElements[0].Visit($this)
    }else{
      return "__runtime__.pipe($(
        (
          $pipeline.PipelineElements | ForEach-Object {
            if ($_ -is [CommandAst]){
              [CommandAst]$command = [CommandAst]$_
              $name = $command.CommandElements[0]
              $args = $command.CommandElements[1..($command.CommandElements.Count)]
              "[$($this.ConvertFuncName($name)), $(($args | ForEach-Object { $_.Visit($this) }) -Join ", " )]"
            }else{ "[$($_.Visit($this))]" }
          }
        ) -Join ", "
      ))"
    }
  }

  [object]VisitConstantExpression([ConstantExpressionAst]$constExpr){
    return ConvertTo-Json $constExpr.Value
  }

  [object]VisitStringConstantExpression([StringConstantExpressionAst]$constExpr){
    return ConvertTo-Json $constExpr.Value
  }

  [object]VisitCommandExpression([CommandExpressionAst]$commandExpr){
    return $commandExpr.Expression.Visit($this)
  }

  [object]VisitCommand([CommandAst]$command){
    [string]$commandName = $this.ConvertFuncName($command.CommandElements[0].ToString())
    if (
      ($command.CommandElements[0].ToString() -eq "const" -or $command.CommandElements[0].ToString() -eq "let")
    ){
      return "$($command.CommandElements[0]) $($command.CommandElements[1].Pipeline.Visit($this))"
    }
    return "$($commandName)($(($command.CommandElements[1..($command.CommandElements.Count)] | ForEach-Object { $_.Visit($this) }) -Join ", "))"
  }

  [object]VisitAssignmentStatement([AssignmentStatementAst]$assign){
    return "$($assign.Left -is [ConvertExpressionAst] ? $assign.Left.Child.Visit($this) : $assign.Left.Visit($this)) = $($assign.Right.Visit($this))"
  }

  [object]VisitMemberExpression([MemberExpressionAst]$memberExpr){
    return "$($memberExpr.Expression.Visit($this)).$($memberExpr.Member -is [StringConstantExpressionAst] ? $memberExpr.Member.Value : $memberExpr.Member.Visit($this))"
  }

  [object]VisitIndexExpression([IndexExpressionAst]$indexExpr){
    return "$($indexExpr.Target.Visit($this))[$($indexExpr.Index.Visit($this))]"
  }

  [object]VisitVariableExpression([VariableExpressionAst]$variable){
    return "$($this.ConvertIdent($variable.VariablePath))"
  }

  [object]VisitInvokeMemberExpression([InvokeMemberExpressionAst]$ime){
    return "$($ime.Expression.Visit($this)).$($ime.Member)($(
      (
        $null -ne $ime.Arguments ? ($ime.Arguments | ForEach-Object { $_.Visit($this) }) : @()
      ) -Join ", "
    ))"
  }

  [object]VisitParenExpression([ParenExpressionAst]$paren){
    return "($(
      $paren.Pipeline.Visit($this)
    ))"
  }

  [object]VisitBinaryExpression([BinaryExpressionAst]$binOp){
    return "$($binOp.Left.Visit($this)) $($binOp.ErrorPosition) $($binOp.Right.Visit($this))"
  }

  [object]VisitFunctionDefinition([FunctionDefinitionAst]$funcDef){
    return "function $($this.ConvertIdent($funcDef.Name))($(
      (
        $null -ne $funcDef.Parameters ? (
          $funcDef.Parameters | ForEach-Object {
            $_.Visit($this)
          }
        ) : @()
      ) -Join ", "
    )){const `$`$__output__ = {add(...values){this.data.push(...values.filter(x => x !== undefined)) }, data: []};$(
      $funcDef.Body.EndBlock.Visit($this)
    );return `$`$__output__.data}"
  }

  [object]VisitParameter([ParameterAst]$params){
    return $params.Name.Visit($this)
  }

  [object]VisitReturnStatement([ReturnStatementAst]$ret){
    return "`$`$__output__.add($($ret.Pipeline.Visit($this))); return `$`$__output__.data"
  }

  [object]VisitScriptBlockExpression([ScriptBlockExpressionAst]$sbe){
    return $sbe.ScriptBlock.Visit($this)
  }

  [object]VisitForEachStatement([ForEachStatementAst]$forEach){
    return "for (const $($forEach.Variable.Visit($this)) of $($forEach.Condition.Visit($this))){$($this.forEach.Body.Visit($this))}"
  }

  [object]VisitStatementBlock([StatementBlockAst]$block){
    return ($block.Statements | ForEach-Object { $_.Visit($this) }) -join "; "
  }
}

function ConvertTo-JavaScript {
  [OutputType([string])]param($scriptblock)
  return @"
const __runtime__ = {
  pipe(...exprs){
    exprs.reduce((p, c) => p ? (typeof c[0] == "function" ? c[0](p, ...c.slice(1)) : c[0]) : typeof c[0] == "function" ? c[0](...c.slice(1)) : c[0], null)
  }
};
"@ + $scriptblock.Ast.Visit([Transpiler]::new())
}

ConvertTo-JavaScript {
  let ($current = $null)

  function ForEach-Object($a, $f) {
    foreach ($x in $a){
      Write-Output $f.call($this, $x)
    }
  }

  function Create-Element($name, $children) {
    $current = $document.createElement($name)
    void ($children.call() | ForEach-Object {
      $current.append($_)
    })
    return $current
  }

  function App() {
    return Create-Element "hoge" {
      return 1234
    }
  }

  App | Write-Host
}

Export-ModuleMember -Function "ConvertTo-JavaScript"