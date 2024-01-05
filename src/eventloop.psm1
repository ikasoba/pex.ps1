using namespace System.Collections.Generic
using namespace System.Threading.Tasks

class Event {
  [Action]$fn
  [Func[bool]]$condition

  Event([Action]$fn, [Func[bool]]$condition){
    $this.fn = $fn
    $this.condition = $condition
  }
}

enum PromiseStatus {
  Pending
  Fulfilled
  Rejected
}

class Promise {
  [PromiseStatus]$status = [PromiseStatus]::Pending
  $value = $null

  Promise(){}

  Resolve($value){
    $this.status = [PromiseStatus]::Fulfilled
    $this.value = $value
  }

  Reject($err){
    $this.status = [PromiseStatus]::Rejected
    $this.value = $err
  }
}

class EventLoop {
  [Queue[Action]]$tasks = [Queue[Action]]::new()
  [Queue[Event]]$events = [Queue[Event]]::new()

  EventLoop(){}

  [Promise]Sleep([int]$miliseconds){
    $promise = [Promise]::new()
    $start = Get-Date
    $this.events.Enqueue([Event]::new(
      {
        $promise.Resolve($null)
      }.GetNewClosure(),
      {
        $time = [int](Get-Date).Subtract($start).TotalMilliseconds
        if ($time -gt $miliseconds){
          return $true
        }else{
          return $false
        }
      }.GetNewClosure()
    ))
    return $promise
  }

  [object]Await([Promise]$promise){
    Start-Sleep -Milliseconds 1
    while ($promise.status -eq [PromiseStatus]::Pending){
      $this.Step()
    }
    if ($promise.status -eq [PromiseStatus]::Rejected){
      throw $promise.value
    }
    return $promise.value
  }

  [void]Step(){
    if ($this.tasks.Count -gt 0){
      $fn = $this.tasks.Dequeue()
      $fn.Invoke()
    }
    if ($this.events.Count -gt 0){
      [Event]$e = $this.events.Dequeue()
      [bool]$res = $e.condition.Invoke()
      if ($res -eq $false){
        $this.events.Enqueue($e)
      }else{
        $e.fn.Invoke()
      }
    }
  }

  [Promise]NewPromise([Action[Promise]]$fn){
    $promise = [Promise]::new()
    $this.tasks.Enqueue({
      $fn.Invoke($promise)
    })
    return $promise
  }

  [Promise]ConvertToPromise([Task[object]]$task){
    $promise = [Promise]::new()
    $this.events.Enqueue([Event]::new(
      {
        if ($task.Status -eq 7 -or $task.Status -eq 6){
          $promise.Reject($task.Exception)
          return
        }
        $promise.Resolve($task.Result)
      },
      {
        return $task.Status -eq 7 -or $task.Status -eq 6 -or $task.Status -eq 5
      }
    ))
    return $promise
  }
}

function New-EventLoop {
  [OutputType([EventLoop])] param()
  return [EventLoop]::new()
}

function New-EventLoopEvent($x, $y){
  return [Event]::new($x, $y)
}

Export-ModuleMember -Function "New-EventLoop", "New-EventLoopEvent"