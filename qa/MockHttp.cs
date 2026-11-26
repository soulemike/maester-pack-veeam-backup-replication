using System;
using System.Collections.Generic;
using System.Net;
using System.Net.Http;
using System.Threading;
using System.Threading.Tasks;
using System.Text;

// Synthetic responses only. This handler is not referenced by production pack code.
public sealed class VbrMockHttpHandler : HttpMessageHandler {
    public readonly Queue<(int Status, string Body, int Retry)> Replies = new();
    public readonly List<string> Requests = new();
    public bool Disposed { get; private set; }
    public void Enqueue(int status, string body, int retry = 0) => Replies.Enqueue((status, body, retry));
    protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token) {
        token.ThrowIfCancellationRequested();
        Requests.Add(request.Method.Method + " " + request.RequestUri.PathAndQuery);
        if (Replies.Count == 0) throw new InvalidOperationException("Mock response queue exhausted");
        var reply = Replies.Dequeue();
        var response = new HttpResponseMessage((HttpStatusCode)reply.Status) {
            Content = new StringContent(reply.Body, Encoding.UTF8, "application/json")
        };
        if (reply.Retry > 0) response.Headers.RetryAfter = new System.Net.Http.Headers.RetryConditionHeaderValue(TimeSpan.FromSeconds(reply.Retry));
        return Task.FromResult(response);
    }
    protected override void Dispose(bool disposing) { Disposed = true; base.Dispose(disposing); }
}

public sealed class VbrUntrustedTlsServer : IDisposable {
    readonly System.Net.Sockets.TcpListener listener;
    readonly System.Security.Cryptography.X509Certificates.X509Certificate2 certificate;
    readonly CancellationTokenSource cancellation = new(TimeSpan.FromSeconds(5));
    readonly Task task;
    public int Port { get; }
    public VbrUntrustedTlsServer() {
        using var rsa = System.Security.Cryptography.RSA.Create(2048);
        var request = new System.Security.Cryptography.X509Certificates.CertificateRequest("CN=localhost", rsa,
            System.Security.Cryptography.HashAlgorithmName.SHA256, System.Security.Cryptography.RSASignaturePadding.Pkcs1);
        certificate = request.CreateSelfSigned(DateTimeOffset.UtcNow.AddMinutes(-1), DateTimeOffset.UtcNow.AddMinutes(10));
        listener = new System.Net.Sockets.TcpListener(IPAddress.Loopback, 0);
        listener.Start(); Port = ((IPEndPoint)listener.LocalEndpoint).Port;
        task = Task.Run(async () => {
            try {
                using var client = await listener.AcceptTcpClientAsync(cancellation.Token);
                using var stream = new System.Net.Security.SslStream(client.GetStream());
                await stream.AuthenticateAsServerAsync(new System.Net.Security.SslServerAuthenticationOptions { ServerCertificate = certificate }, cancellation.Token);
            } catch { /* A rejected self-signed certificate is the expected synthetic scenario. */ }
        });
    }
    public void Dispose() {
        cancellation.Cancel(); listener.Stop();
        try { task.GetAwaiter().GetResult(); } catch { }
        certificate.Dispose(); cancellation.Dispose();
    }
}
