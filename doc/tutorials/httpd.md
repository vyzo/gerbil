# Web programming with the Gerbil http server

## Preliminaries

In this tutorial we illustrate web programming with the embedded Gerbil http server.

This tutorial requires a very recent version of Gambit that supports raw devices ([gambit#272](https://github.com/gambit/gambit/pull/272)).

The source code for the tutorial  is available at [$GERBIL_HOME/src/tutorial/httpd](https://github.com/vyzo/gerbil/tree/master/src/tutorial/httpd).
You can build the source code using the build script:
```bash
$ cd $GERBIL_HOME/src/tutorial/httpd
$ ./build.ss

```

This builds a single binary, `simpled`, in the tutorial directory.

## A Simple Web Server

The [server](https://github.com/vyzo/gerbil/blob/master/src/tutorial/httpd/simpled.ss) binds by default to localhost:8080
and handles 3 request URLs:
- `/` which greets the requestor
- `/echo` which echoes back the body of the request
- `/headers[?json]` which echoes back the request headers
- `/self` which prints the source code of the program
- `/template` which renders the *template.html* template

### The main function

The server `main` function uses getopt to parse arguments and then
calls the `run` function. It starts an http server using the default
handler multiplexer, and registers handlers using `http-register-handler`
for the various paths we want to handle:
```scheme
(def (main . args)
  (def gopt
    (getopt (option 'address "-a" "--address"
                    help: "server address"
                    default: "127.0.0.1:8080")))

  (try
   (let (opt (getopt-parse gopt args))
     (run (hash-get opt 'address)))
   (catch (getopt-error? exn)
     (getopt-display-help exn "hellod" (current-error-port))
     (exit 1))))

(def (run address)
  (let (httpd (start-http-server! address mux: (make-default-http-mux default-handler)))
    (http-register-handler httpd "/" root-handler)
    (http-register-handler httpd "/echo" echo-handler)
    (http-register-handler httpd "/headers" headers-handler)
    (http-register-handler httpd "/self" self-handler)
    (http-register-handler httpd "/template" template-handler)
    (thread-join! httpd)))
```

### Request Handlers

Request handlers are functions that accept two arguments: a request
and a response object. The request object bundles the request together,
while the response object offers an interface to write the response.
Request handlers are dispatched in a new thread.

#### The `/` handler

The root handler simply prints a hello message:
```scheme
(def (root-handler req res)
  (http-response-write res 200 '(("Content-Type" . "text/plain"))
    (string-append "hello, " (inet-address->string (http-request-client req)) "\n")))
```

#### The `/echo` handler

The echo handler echoes back the body of the request:
```scheme
(def (echo-handler req res)
  (let* ((content-type
          (assget "Content-Type" (http-request-headers req)))
         (headers
          (if content-type
            [["Content-Type" . content-type]]
            [])))
    (http-response-write res 200 headers
      (http-request-body req))))
```

#### The `/headers` handler

The headers handler responds with the headers of the request,
either in plain text or in json if requested so with a `?json`
parameter. The plain text handler uses the chunked response
interface.

```scheme
(def (headers-handler req res)
  (let (headers (http-request-headers req))
    (if (equal? (http-request-params req) "json")
      (write-json-headers res headers)
      (write-text-headers res headers))))

(def (write-json-headers res headers)
  (let (content
        (json-object->string
         (list->hash-table headers)))
    (http-response-write res 200 '(("Content-Type" . "application/json"))
      content)))

(def (write-text-headers res headers)
  (http-response-begin res 200 '(("Content-Type" . "text/plain")))
  (for ([key . val] headers)
    (http-response-chunk res (string-append key ": " val "\n")))
  (http-response-end res))

```

#### The `/self` handler

The self handler responds by printing the server source code.
The handler uses the `http-response-file` procedure, which sends
a file as an http response using fast raw device I/O.

```scheme
(def (self-handler req res)
  (http-response-file res '(("Content-Type" . "text/plain")) "simpled.ss"))
```

#### The `/template` handler

The macros from `std/misc/text` can be used to generate HTML ressponses.
This handler includes the *template.html* template, which is parsed with
`quasistring*` as it contains expansion-time template variables.

See `std/misc/text` for details on the macros.

```scheme
(def (template-handler req res)
  (def (json-ref key)
    (let* ((json (read-json (open-input-u8vector (http-request-body req))))
           (ref (hash-ref json key)))
      (if ref
        ref
        (string-append "Key " key " not found."))))

  ;; title and h1 are run-time template variables
  (def (t title h1)
    (include-quasistring* "templates/template.html"))

  (http-response-write res 200 '(("Content-Type" . "text/html"))
    (t "Title" "Hey!")))
```

Here is *template.html*:

```html
<html>
    <head>
        <title>#{title}</title>
    </head>
    <body>
        <h1>#{h1}</h1>

        <!-- sub-template -->
        ##{(include-text "templates/subtemplate.html")}

        <h3>Your message is: #{(json-ref 'message)}</h3>
    </body>
</html>
```

And here is *subtemplate.html*:

```html
<div>
    <h2>This is a subtemplate.</h2>
    <div>
        ##{(sxml->html-string-fragment
        (cons 'ul (for/fold (l []) (i (in-range 10))
        (append l [['li i]]))))}
    </div>
</div>
```

#### The default handler

The default handler is invoked when there is no matching handler.
If no default handler is registered with the multiplexer, then the server
simply responds with a 404.

Here, we registered a slightly friendlier handler that uses the force to
print an informative message:
```scheme
(def (default-handler req res)
  (http-response-write res 404 '(("Content-Type" . "text/plain"))
    "these aren't the droids you are looking for.\n"))
```

### Examples

Here are some example interactions with the server using curl:
```bash
$ ./simpled &

$ curl http://localhost:8080/
hello, 127.0.0.1:39189

$ curl --data-binary "hello gerbil" http://localhost:8080/echo
hello gerbil

$ curl http://localhost:8080/headers
Host: localhost:8080
User-Agent: curl/7.45.0
Accept: */*

$ curl http://localhost:8080/headers?json
{"Accept":"*/*","Host":"localhost:8080","User-Agent":"curl/7.45.0"}

$ curl -i http://localhost:8080/bogus
HTTP/1.1 404 Not Found
Date: Tue Aug 22 16:16:19 2017
Content-Length: 45
Content-Type: text/plain

these aren't the droids you are looking for.

$ curl -d '{"message": "Hello, world!"}' -H "Content-Type: application/json" -X POST http://localhost:8080/template

<html>
    <head>
        <title>Title</title>
    </head>
    <body>
        <h1>Hey!</h1>

        <!-- sub-template -->
        <div>
    <h2>This is a subtemplate.</h2>
    <div>
        <ul><li>0</li><li>1</li><li>2</li><li>3</li><li>4</li><li>5</li><li>6</li><li>7</li><li>8</li><li>9</li></ul>
    </div>
</div>


        <h3>Your message is: Hello, world!</h3>
    </body>
</html>
```
