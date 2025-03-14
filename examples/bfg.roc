app [main!] {
    pf: platform "../platform/main.roc",
    json: "https://github.com/lukewilliamboswell/roc-json/releases/download/0.12.0/1trwx8sltQ-e9Y2rOB4LWUWLS_sFVyETK8Twl0i9qpw.tar.gz",
}

import pf.Stdout
import pf.Http
import pf.Env
import json.Json
import pf.Tcp

url = "https://identitysso.betfair.se/api/login"

main! = |_args|
    app_key = Env.var!("BFG_APP_KEY")?
    username = Env.var!("BFG_USERNAME")?
    password = Env.var!("BFG_PASSWORD")?
    dbg (app_key, username, password)
    response = Http.send!(
        {
            method: POST,
            headers: [
                { name: "Accept", value: "application/json" },
                { name: "X-Application", value: app_key },
                { name: "Content-Type", value: "application/x-www-form-urlencoded" },
            ],
            uri: url,
            body: Str.to_utf8("username=${username}&password=${password}"),
            timeout_ms: TimeoutMilliseconds(5000),
        },
    )?

    Login : {
        token : Str,
        product : Str,
        status : Str,
        error : Str,
    }

    body : Result Login _
    body =
        response.body
        |> Decode.from_bytes(Json.utf8)

    stream_url = "stream-api-integration.betfair.com"
    port = 443
    AuthMessage : {
        op : Str,
        appKey : Str,
        session : Str,
    }

    authMessage : AuthMessage
    authMessage = {
        op: "authentication",
        appKey: app_key,
        session: body?.token,
    }

    stream = Tcp.connect!(stream_url, port)?

    msg =
        authMessage
        |> Encode.to_bytes(Json.utf8)
        |> List.concat_utf8("\r\n")
    Tcp.write!(stream, msg)?

    ConnResp : { op : Str, connectionId : Str }

    resp : ConnResp
    resp =
        stream
        |> Tcp.read_line!()?
        |> Str.to_utf8
        |> Decode.from_bytes(Json.utf8)?

    dbg resp

    Stdout.line!("DONE")

