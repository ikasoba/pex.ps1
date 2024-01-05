using namespace System
using namespace System.Net
using namespace System.Threading.Tasks
using namespace System.Collections.Generic
using namespace System.Web

using module ./pex.psd1

$el = New-EventLoop

$app = New-Router $el

[List[Tuple[string, string, bool]]]$todos = @()

$app.post("/new-todo", {
  param($context, $next)

  $body = (Read-RequestBody $context.Request | ConvertFrom-WwwFormUrlencoded)

  $todos.Add([Tuple[string, string, bool]]::new($body["title"], $body["description"], $false))

  $context.Response.StatusCode = 301
  $context.Response.RedirectLocation = "/"
  $context.Response.Close()
})

$app.get("/", {
  param($context, $next)

  $context.Response.AddHeader("Content-Type", "text/html")

  $res = [System.Text.UTF8Encoding]::new($false).GetBytes((
  Invoke-Template @'
<?pwsh param($context, $todos)
?><!doctype html>
<html>
<head>
    <meta charset="UTF-8" />
</head>
<body>
  <h1>Todo App</h1>
  <form action="/new-todo" method="POST" enctype="application/x-www-form-urlencoded" accept-charset="UTF-8">
    <label>
      title:
      <input name="title" type="text" placeholder="Buy 3 apples." />
    </label><br/>
    <label>
      description:<br/>
      <textarea name="description" placeholder="Because we don't have enough."></textarea>
    </label><br/>
    <input type="submit"/>
  </form>
  <?pwsh foreach ($item in $todos) { ?>
    <div>
      title: <?=$item[0] ?><br/>
      description:
      <div style="white-space: pre; padding-left: 1rem;"><?=$item[1] ?></div>
      <label><input type="checkbox" <?= $item[2] ? "checked" : "" ?>/>is completed?</label>
    </div>
  <?pwsh } ?>
</body>
</html>
'@ -Arguments @($context, $todos)
  ))
  $context.Response.OutputStream.Write($res)
  $context.Response.Close()
})

$app.Listen(4000, "127.0.0.1")

Write-Host "Server Started! Listening at https://127.0.0.1:4000/"

while ($true){
  $el.Step()
}