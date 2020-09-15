module RuntimeGeneratedFunctions

using ExprTools, Serialization, SHA

export @RuntimeGeneratedFunction


"""
    RuntimeGeneratedFunction

This type should be constructed via the macro @RuntimeGeneratedFunction.
"""
struct RuntimeGeneratedFunction{moduletag,id,argnames}
    body::Expr
    function RuntimeGeneratedFunction(moduletag, ex)
        def = splitdef(ex)
        args, body = normalize_args(def[:args]), def[:body]
        id = expr2bytes(body)
        cached_body = _cache_body(moduletag, id, body)
        new{moduletag,id,Tuple(args)}(cached_body)
    end
end

"""
    @RuntimeGeneratedFunction(function_expression)

Construct a function from `function_expression` which can be called immediately
without world age problems. Somewhat like using `eval(function_expression)` and
then calling the resulting function. The differences are:

* The result can be called immediately (immune to world age errors)
* The result is not a named generic function, and doesn't participate in
  generic function dispatch; it's more like a callable method.

# Examples
```
function foo()
    expression = :((x,y)->x+y+1) # May be generated dynamically
    f = @RuntimeGeneratedFunction(expression)
    f(1,2) # May be called immediately
end
```
"""
macro RuntimeGeneratedFunction(ex)
    _ensure_cache_exists!(__module__)
    quote
        RuntimeGeneratedFunction(
            $(esc(_tagname)),
            $(esc(ex))
        )
    end
end

function Base.show(io::IO, f::RuntimeGeneratedFunction{moduletag, id, argnames}) where {moduletag,id,argnames}
    mod = parentmodule(moduletag)
    func_expr = Expr(:->, Expr(:tuple, argnames...), f.body)
    print(io, "RuntimeGeneratedFunction(#=in $mod=#, ", repr(func_expr), ")")
end

(f::RuntimeGeneratedFunction)(args::Vararg{Any,N}) where N = generated_callfunc(f, args...)

@inline @generated function generated_callfunc(f::RuntimeGeneratedFunction{moduletag, id, argnames}, __args...) where {moduletag,id,argnames}
    setup = (:($(argnames[i]) = @inbounds __args[$i]) for i in 1:length(argnames))
    body = _lookup_body(moduletag, id)
    @assert body !== nothing
    quote
        $(setup...)
        $(body)
    end
end

### Body caching and lookup
#
# Looking up the body of a RuntimeGeneratedFunction based on the id is a little
# complicated because we want the `id=>body` mapping to survive precompilation.
# This means we need to store the mapping created by a module in that module
# itself.
#
# For that, we need a way to lookup the correct module from an instance of
# RuntimeGeneratedFunction. Modules can't be type parameters, but we can use
# any type which belongs to the module as a proxy "tag" for the module.
#
# (We could even abuse `typeof(__module__.eval)` for the tag, though this is a
# little non-robust to weird special cases like Main.eval being
# Base.MainInclude.eval.)

# It appears we can't use a ReentrantLock here, as contention seems to lead to
# deadlock. Perhaps because it triggers a task switch while compiling the
# @generated function.
_cache_lock = Threads.SpinLock()
_cachename = Symbol("#_RuntimeGeneratedFunctions_cache")
_tagname = Symbol("#_RuntimeGeneratedFunctions_ModTag")

function _cache_body(moduletag, id, body)
    lock(_cache_lock) do
        cache = getfield(parentmodule(moduletag), _cachename)
        # Caching is tricky when `id` is the same for different AST instances:
        #
        # Tricky case #1: If a function body with the same `id` was cached
        # previously, we need to use that older instance of the body AST as the
        # canonical one rather than `body`. This ensures the lifetime of the
        # body in the cache will always cover the lifetime of the parent
        # `RuntimeGeneratedFunction`s when they share the same `id`.
        #
        # Tricky case #2: Unless we hold a separate reference to
        # `cache[id].value`, the GC can collect it (causing it to become
        # `nothing`). So root it in a local variable first.
        #
        cached_body = haskey(cache, id) ? cache[id].value : nothing
        cached_body = cached_body !== nothing ? cached_body : body
        # Use a WeakRef to allow `body` to be garbage collected. (After GC, the
        # cache will still contain an empty entry with key `id`.)
        cache[id] = WeakRef(cached_body)
        return cached_body
    end
end

function _lookup_body(moduletag, id)
    lock(_cache_lock) do
        cache = getfield(parentmodule(moduletag), _cachename)
        cache[id].value
    end
end

function _ensure_cache_exists!(mod)
    lock(_cache_lock) do
        if !isdefined(mod, _cachename)
            mod.eval(quote
                const $_cachename = Dict()
                struct $_tagname
                end
            end)
        end
    end
end

###
### Utilities
###
normalize_args(args::Vector) = map(normalize_args, args)
normalize_args(arg::Symbol) = arg
function normalize_args(arg::Expr)
    arg.head === :(::) || error("argument malformed. Got $arg")
    arg.args[1]
end

function expr2bytes(ex)
    io = IOBuffer()
    Serialization.serialize(io, ex)
    return Tuple(sha512(take!(io)))
end

end
