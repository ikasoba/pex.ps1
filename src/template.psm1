function Convert-Template {
  param([string]$src)

  $res = ""
  $isScriptMode = $false

  function Skip-WhiteSpace([int]$i){
    While (($src[$i] -eq " ") -or ($src[$i] -eq "`t") -or ($src[$i] -eq "`r") -or ($src[$i] -eq "`n")){
      $i += 1
    }
    return $i
  }

  function Begin-Script([int]$i, [bool]$check = $false){
    $resIndex = $i
    if ($src.Substring($resIndex).StartsWith("<?pwsh")){
      $resIndex += "<?pwsh".Length
      $prevIndex = $resIndex
      $resIndex = Skip-WhiteSpace $resIndex
      if ($prevIndex -eq $resIndex){
        return $isScriptMode, $i
      }
      if ($check -eq $false){
        $isScriptMode = $true
      }
      return $isScriptMode, $resIndex
    }elseif ($src.Substring($resIndex).StartsWith("<?=")){
      $resIndex += "<?=".Length
      if ($check -eq $false){
        $isScriptMode = $true
      }
      return $isScriptMode, $resIndex
    }
    return $isScriptMode, $i
  }

  function End-Script([int]$i, [bool]$check = $false){
    $resIndex = $i
    if ($src.Substring($resIndex).StartsWith("?>")){
      $resIndex += "?>".Length
    }else{ return $isScriptMode, $i }
    if ($check -eq $false){
      $isScriptMode = $false
    }
    return $isScriptMode, $resIndex
  }

  function Add-Text([int]$i){
    $res = ""
    $tmp = ""
    while ($i -lt $src.Length){
      if ($isScriptMode){
        if ((End-Script $i $true)[1] -ne $i){
          return $res, $i
        }
        $res += $src[$i]
      }else{
        if ((Begin-Script $i $true)[1] -ne $i){
          if ($tmp.Length -gt 0){
            $res += "`nWrite-Output `"$($tmp -replace '[\r\n"]', '`$0')`"`n"
            $tmp = ""
          }
          return $res, $i
        }
        $tmp += $src[$i]
      }
      $i += 1
    }
    if ($tmp.Length -gt 0){
      $res += "`nWrite-Output `"$($tmp -replace '[\r\n"]', '`$0')`"`n"
      $tmp = ""
    }
    return $res, $i
  }

  for ($i = 0; $i -lt $src.Length; ){
    $n = 0
    foreach ($parser in {param($x); Add-Text $x}, {param($x); Begin-Script $x}, {param($x); End-Script $x}){
      $prevIndex = $i
      $tmp = &$parser $i
      if ($n -eq 0){
        $res += $tmp[0]
      }else{
        $isScriptMode = $tmp[0]
      }
      $i = $tmp[1]
      if ($prevIndex -eq $i){
        $i = $prevIndex
        $n += 1
        continue
      }
      break
    }
  }
  return $res
}

function Invoke-Template {
  param([string]$Source, [object[]]$Arguments = @(), [hashtable]$Functions = @{}, [System.Collections.Generic.List[psvariable]]$Variables = @())
  $code = Convert-Template $Source
  $res = [Scriptblock]::Create($code).InvokeWithContext($Functions, $Variables, $Arguments)
  return [string]::Join("", $res)
}

Export-ModuleMember -Function "Convert-Template", "Invoke-Template"