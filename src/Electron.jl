__precompile__()
module Electron

using JSON, URIParser

export Application, Window

struct Application
    id::UInt
    connection
    proc
end

struct Window
    app::Application
    id::Int
end

const _global_application = Ref{Nullable{Application}}(Nullable{Application}())
const _global_application_next_id = Ref{Int}(1)

function __init__()
    _global_application[] = Nullable{Application}()
    _global_application_next_id[] = 1
end

function generate_pipe_name(name)
    if is_windows()
        "\\\\.\\pipe\\$name"
    elseif is_unix()
        joinpath(tempdir(), name)
    end
end

function get_electron_binary_cmd()
    @static if is_apple()
        return joinpath(@__DIR__, "..", "deps", "Julia.app", "Contents", "MacOS", "Julia")
    elseif is_linux()
        return joinpath(@__DIR__, "..", "deps", "electron", "electron")
    elseif is_windows()
        return joinpath(@__DIR__, "..", "deps", "electron", "electron.exe")
    else
        error("Unknown platform.")
    end
end

"""
    function Application()

Start a new Electron application. This will start a new process
for that Electron app and return an instance of `Application` that
can be used in the construction of Electron windows.
"""
function Application()
    electron_path = get_electron_binary_cmd()
    mainjs = joinpath(@__DIR__, "main.js")
    id = _global_application_next_id[]
    _global_application_next_id[] = id + 1
    process_id = getpid()
    pipe_name = "juliaelectron-$process_id-$id"
    named_pipe_name = generate_pipe_name(pipe_name)

    server = listen(named_pipe_name)

    proc = spawn(`$electron_path $mainjs $pipe_name`)

    sock = accept(server)

    return Application(id, sock, proc)
end

"""
    close(app::Application)

Terminates the Electron application referenced by `app`.
"""
function Base.close(app::Application)
    close(app.connection)
end

"""
    run(app::Application, code::AbstractString)

Run the JavaScript code that is passed in `code` in the main
application thread of the `app` Electron process. Returns the
value that the JavaScript expression returns.
"""
function Base.run(app::Application, code::AbstractString)
    println(app.connection, JSON.json(Dict("target"=>"app", "code"=>code)))
    retval_json = readline(app.connection)
    retval = JSON.parse(retval_json)
    return retval["data"]
end

"""
    run(win::Window, code::AbstractString)

Run the JavaScript code that is passed in `code` in the render
thread of the `win` Electron windows. Returns the value that
the JavaScript expression returns.
"""
function Base.run(win::Window, code::AbstractString)
    message = Dict("target"=>"window", "winid" => win.id, "code" => code)
    println(win.app.connection, JSON.json(message))
    retval_json = readline(win.app.connection)
    retval = JSON.parse(retval_json)
    return retval["data"]
end

"""
    function Window(app::Application, uri::URI)

Open a new Window in the application `app`. Show the content
that `uri` points to in that new window.
"""
function Window(app::Application, uri::URI)
    json_options = JSON.json(Dict("url"=>string(uri)))
    code = "createWindow($json_options)"
    ret_val = run(app, code)
    return Window(app, ret_val)
end

"""
    function Window(uri::URI)

Open a new Window in the default Electron application. If no
default application is running, first start one. Show the content
that `uri` points to in that new window.
"""
function Window(uri::URI)
    if isnull(_global_application[])
        _global_application[] = Nullable(Application())
    end

    return Window(get(_global_application[]), uri)
end

end
