using System;
using System.Net;
using System.Threading;
using System.Threading.Tasks;
using System.Collections.Concurrent;

public class HttpServer {
  public HttpListener listener = new HttpListener();
  public ConcurrentQueue<HttpListenerContext> contexts = new ConcurrentQueue<HttpListenerContext>();

  public async Task StartWaitRequests(){
    while (this.listener.IsListening){
      var context = await this.listener.GetContextAsync();
      this.contexts.Enqueue(context);
    }
  }
}