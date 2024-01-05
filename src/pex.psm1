using namespace System
using namespace System.Net
using namespace System.Threading.Tasks
using namespace System.Collections.Generic
using namespace System.Web

using module ./eventloop.psm1
using module ./template.psm1
Add-Type -TypeDefinition $(Get-Content (Join-Path $PSScriptRoot ./HttpServer.cs) -Raw) -Language CSharp

function New-HttpServer {
  return [HttpServer]::new()
}

<#
  .DESCRIPTION
  最小限なHttpサーバー
#>
class SimpleHttpServer {
  $httpServer = (New-HttpServer)
  $eventLoop
  [Action[HttpListenerContext]]$handler

  SimpleHttpServer($EventLoop, [Action[HttpListenerContext]]$Handler){
    $this.eventLoop = $EventLoop
    $this.handler = $Handler
  }

  [object]GetEventLoop(){
    return $this.eventLoop
  }

  [HttpListener]GetListener(){
    return $this.httpServer.listener
  }

  [void]Listen([int]$Port = 8080, [string]$Hostname = "127.0.0.1"){
    $this.httpServer.listener.Prefixes.Add("http://${hostname}:${port}/")
    $this.httpServer.listener.Start()
    $this.httpServer.StartWaitRequests() > $null

    $this.eventLoop.events.Enqueue((
      New-EventLoopEvent {} {
        $self = $script:this
        if ($self.httpServer.contexts.Count){
          [HttpListenerContext]$context = $null
          if ($self.httpServer.contexts.TryDequeue([ref]$context)){
            $self.eventLoop.tasks.Enqueue({
              $self.handler.Invoke($context)
            }.GetNewClosure())
          }
        }
        return $false
      }.GetNewClosure()
    ))
  }
}

class PexRoutes {
  [Dictionary[string, List[Tuple[string, Action[HttpListenerContext, Action]]]]]$data = @{}

  PexRoutes() {}

  Add([string]$method, [string]$path, [Action[HttpListenerContext, Action]]$handler){
    if ($null -eq $this.data[$path]){
      $this.data[$path] = @()
    }
    $this.data[$path].Add([Tuple[string, Action[HttpListenerContext, Action]]]::new($method, $handler))
  }

  [List[Tuple[string, Action[HttpListenerContext, Action]]]]Get([string]$path){
    return $this.data[$path]
  }
}

class PexRouter {
  [PexRoutes]$routes = [PexRoutes]::new()
  [SimpleHttpServer]$server
  $eventLoop

  PexRouter($eventLoop){
    $this.eventLoop = $eventLoop
    $this.server = $null
  }

  Route([string]$path, [Action[HttpListenerContext, Action]]$handler){
    $this.routes.Add("*", $path, $handler)
  }

  Route([string]$method, [string]$path, [Action[HttpListenerContext, Action]]$handler){
    $this.routes.Add($method, $path, $handler)
  }

  get([string]$path, [Action[HttpListenerContext, Action]]$handler){
    $this.Route("GET", $path, $handler)
  }

  head([string]$path, [Action[HttpListenerContext, Action]]$handler){
    $this.Route("HEAD", $path, $handler)
  }

  post([string]$path, [Action[HttpListenerContext, Action]]$handler){
    $this.Route("POST", $path, $handler)
  }

  put([string]$path, [Action[HttpListenerContext, Action]]$handler){
    $this.Route("PUT", $path, $handler)
  }

  delete([string]$path, [Action[HttpListenerContext, Action]]$handler){
    $this.Route("DELETE", $path, $handler)
  }

  connect([string]$path, [Action[HttpListenerContext, Action]]$handler){
    $this.Route("CONNECT", $path, $handler)
  }

  options([string]$path, [Action[HttpListenerContext, Action]]$handler){
    $this.Route("OPTIONS", $path, $handler)
  }

  trace([string]$path, [Action[HttpListenerContext, Action]]$handler){
    $this.Route("TRACE", $path, $handler)
  }

  patch([string]$path, [Action[HttpListenerContext, Action]]$handler){
    $this.Route("PATCH", $path, $handler)
  }

  [void]Listen([int]$Port = 8080, [string]$Hostname = "127.0.0.1"){
    if ($null -eq $this.server){
      $this.server = [SimpleHttpServer]::new($this.eventLoop, {
        param([HttpListenerContext]$ctx)
        $self = $script:this
        $path = $ctx.Request.Url.AbsolutePath
        $i = 0
        $routes = $self.routes.Get($path)
        $method = $ctx.Request.HttpMethod
        $next = {
          for (;$script:i -lt $script:routes.Count; $script:i += 1){
            if (($script:routes[$script:i].Item1.ToLower() -eq "*") -or ($script:routes[$script:i].Item1.ToLower() -eq $method.ToLower())){
              $script:routes[$script:i].Item2.Invoke($ctx, $script:next)
              $script:i += 1
              return
            }
            continue
          }
          if ($script:i -ge $routes.Count){
            $ctx.Response.StatusCode = 404
            $ctx.Response.AddHeader("Content-Type", "text/plain; charset=UTF-8")
            $ctx.Response.OutputStream.Write([System.Text.UTF8Encoding]::new().GetBytes(
@"
404 not found.
Location at "${path}".
"@
            ))
            $ctx.Response.Close()
          }
        }.GetNewClosure()
        $next.Invoke()
      }.GetNewClosure())
    }
    $this.server.Listen($Port, $Hostname)
  }
}

function New-SimpleHttpServer {
  [OutputType([SimpleHttpServer])] param($eventLoop, [Action[HttpListenerContext]]$handler)
  return [SimpleHttpServer]::new($eventLoop, $handler)
}

function New-Router {
  [OutputType([PexRouter])] param($eventLoop)
  return [PexRouter]::new($eventLoop)
}

function ConvertFrom-WwwFormUrlencoded {
  [OutputType([Dictionary[string, string]])] param([string]$Source, [Text.Encoding]$Encoding = [Text.UTF8Encoding]::new($false))
  $in = $input | ForEach-Object { $_ }
  if ($in.Count -gt 0){
    return $in | ForEach-Object { ConvertFrom-WwwFormUrlencoded $_ $Encoding }
  }
  $entries = [List[KeyValuePair[string, string]]](
    $Source.Split("&") | ForEach-Object {
      $kv = $_.Split("=") | ForEach-Object {
        return [HttpUtility]::UrlDecode($_, $Encoding)
      }
      return [KeyValuePair[string, string]]::new($kv[0], $kv[1])
    }
  )
  return [Dictionary[string, string]]::new($entries)
}

function Read-RequestBody {
  [OutputType([string])] param([HttpListenerRequest]$Request, [Text.Encoding]$Encoding = [Text.UTF8Encoding]::new($false))
  $in = $input | ForEach-Object { $_ }
  if ($in.Count -gt 0){
    return $in | ForEach-Object { Read-RequestBody $_, $Encoding }
  }
  $length = $Request.ContentLength64
  $buf = [array]::CreateInstance([byte].AsType(), $length)
  $Request.InputStream.Read($buf, 0, $length) > $null
  $decoder = $Encoding.GetDecoder()
  $tmp = [array]::CreateInstance([char].AsType(), $decoder.GetCharCount($buf, 0, $buf.Length))
  $decoder.GetChars($buf, 0, $buf.Length, $tmp, 0) > $null
  return [string]::Join("", $tmp)
}

function HTMLEncode {
  param([string]$Source)
  # なぜか$inputが参照しただけで$nullに変わっちゃうのでコピー
  $in = $input | ForEach-Object { $_ }
  if ($in.Count -gt 0){
    return $in | ForEach-Object { HTMLEncode $_ }
  }
  [HttpUtility]::HtmlEncode($Source)
}

Export-ModuleMember -Function *