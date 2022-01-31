#
# Copyright 2021 Clemens Cords
# Created on 26.12.2021 by clem (mail@clemens-cords.com)
#

module jluna

    """
    get_value_type_of_array(::Array{T}) -> Type

    forward value type of array
    """
    function get_value_type_of_array(_::Array{T}) ::Type where T

        return T
    end

    """
    get_reference_value(::Base.RefValue{T}) -> T

    forward value of reference
    """
    function get_reference_value(ref::Base.RefValue{T}) ::T where T

        return ref[];
    end

    setindex!(str::String, c::Char, i::Int64) = setindex!(collect(str), c, i)

    """
    is_number_only(::String) -> Bool

    check whether a string can be transformed into a base 10 number
    """
    function is_number_only(x::String) ::Bool

        for s in x
            if s != '0' || s != '1' || s != '2' || s != '3' || s != '4' || s != '5' || s != '6' || s != '7' || s != '8' || s != '9'
                return false
            end
        end

        return true;
    end

    """
    is_method_available(::Function, ::Any) -> Bool

    check if method of given function is available for a specific variable
    """
    function is_method_available(f::Function, variable) ::Bool

        return hasmethod(f, Tuple{typeof(variable)})
    end

    """
    get_function(::Symbol, ::Module) -> Function

    exception-safe function access wrapper
    """
    function get_function(function_name::Symbol, m::Module) ::Function

        return m.eval(function_name)
    end
    export get_function

    """
    exists(<:AbstractArray, ::Any) -> Bool

    check if element exists in array
    """
    function exists(array::T, v::Any) ::Bool where T <: AbstractArray

        return !isempty(findall(x -> x == v, array))
    end

    """
    tuple_at(::Tuple, ::Integer) -> Any

    get nth element of tuple
    """
    function tuple_at(x::Tuple, i::Integer)
        return x[i]
    end

    """
    make_vector(::T...) -> Vector{T}

    wrap vector ctor in varargs argument, used by box/unbox
    """
    function make_vector(args::T...) ::Vector{T} where T

        return [args...]
    end

    """
    make_set(::T...) -> Set{T}

    wrap set ctor in varargs argument, used by box/unbox
    """
    function make_set(args::T...) ::Set{T} where T

        return Set([args...]);
    end

    """
    assert_isa(::T, ::Symbol) -> Nothing

    throw assertion if x is not of named type
    """
    function assert_isa(x::Any, type_name::Symbol) ::Nothing

        type = Main.eval(type_name);
        @assert type isa Type

        if !(x isa type)
            throw(AssertionError("expected " * string(type) * " but got an object of type " * string(typeof(x))));
        end

        return nothing
    end

    """
    convert(::T, symbol::Symbol) -> Any

    convert value type, declared via symbol
    """
    function convert(x::T, symbol::Symbol) ::Any where T

        type = Main.eval(symbol);
        @assert type isa Type

        if T isa type
            return T
        end

        return Base.convert(type, x)
    end

    """
    invoke(function::Any, arguments::Any...) -> Any

    wrap function call for non-function objects
    """
    function invoke(x::Any, args...) ::Any
        return x(args...)
    end

    """
    serialize(<:AbstractDict{T, U}) -> Vector{Pair{T, U}}

    transform dict into array
    """
    function serialize(x::T) ::Vector{Pair{Key_t, Value_t}} where {Key_t, Value_t, T <: AbstractDict{Key_t, Value_t}}

        out = Vector{Pair{Key_t, Value_t}}()
        for e in x
            push!(out, e)
        end
        return out;
    end

    """
    serialize(::Set{T}) -> Vector{T}

    transform dict into array
    """
    function serialize(x::T) ::Vector{U} where {U, T <: AbstractSet{U}}

        out = Vector{U}()

        for e in x
            push!(out, e)
        end
        return out;
    end

    """
    dot(::Array, field::Symbol) -> Any

    wrapped dot operator
    """
    function dot(x::Array, field_name::Symbol) ::Any

        index_maybe = parse(Int, string(field_name));
        @assert index_maybe isa Integer
        return x[index_maybe];
    end
    export dot;

    """
    dot(::Module, field::Symbol) -> Any

    wrapped dot operator
    """
    dot(x::Module, field_name::Symbol) = return x.eval(field_name);

    """
    dot(x::Any, field::Symbol) -> Any

    wrapped dot operator, x.field
    """
    dot(x::Any, field_name::Symbol) = return eval(:($x.$field_name))

    """
    unquote(::Expr) -> Expr

    remove all line number notes and the outer most :quote block from an expression
    """
    macro unquote(expr::Expr)

        function aux!(args::Vector{Any}) ::Nothing

            to_delete = Vector{Integer}()
            for (i, x) in enumerate(args)
                if x isa LineNumberNode
                    push!(to_delete, i)
                elseif x isa Expr
                    aux!(x.args)
                end
            end

            n_deleted = 0;
            for i in to_delete
                deleteat!(args, i - n_deleted)
                n_deleted += 1
            end
        end

        aux!(expr.args)
        return Expr(expr.head, :($(expr.args...)))
    end

    """
    offers verbose exception interface. Any call with safe_call will store
    the last exception and full stack trace as string in _last_exception and
    _last_message respectively
    """
    module exception_handler

        """
        exception Placeholder that signals that no exception occurred
        """
        struct NoException <: Exception end
        export NoException

        """
        current state of the exception handler

        _last_exception <:Exception
        _last_message ::String
        """
        mutable struct State
            _last_exception
            _last_message::String
        end

        const _state = Ref{State}(State(NoException(), ""));

        """
        `safe_call(::Expr, ::Module = Main) -> Any`

        call any line of code, update the handler then forward the result, if any
        """
        function safe_call(expr::Expr, m::Module = Main) ::Any

            if expr.head == :block
                expr.head = :toplevel
            end

            result = undef
            try
                result = Base.eval(m, expr)
                update()
            catch exc
                result = nothing
                update(exc)
            end

            return result
        end

        """
        `unsafe_call(::Expr, ::Module = Main) -> Any`

        call any line of code without updating the handler
        """
        function unsafe_call(expr::Expr, m::Module = Main) ::Any

            if expr.head == :block
                expr.head = :toplevel
            end

            return Base.eval(m, expr);
        end

        """
        `safe_call(::Function, ::Any...) -> Any`

        call any function, update the handler then forward the result, if any
        """
        function safe_call(f::Function, args...)

            result = undef
            try
                result = f(args...)
                update()
            catch exc
                result = nothing
                update(exc)
            end

            return result;
        end

        """
        `update(<:Exception) -> Nothing`

        update the handler after an exception was thrown
        """
        function update(exception::Exception) ::Nothing

            try
            global _state[]._last_message = sprint(Base.showerror, exception, catch_backtrace())
            global _state[]._last_exception = exception
            catch e end
            return nothing
        end

        """
        `update() -> Nothing`

        update the handler after *no* exception was thrown
        """
        function update() ::Nothing

            global _state[]._last_message = ""
            global _state[]._last_exception = NoException()
            return nothing
        end

        """
        `has_exception_occurred() -> Bool`

        is last exception type no "jluna.exception_handler.NoException"
        """
        function has_exception_occurred() ::Bool

            return typeof(_state[]._last_exception) != NoException
        end

        """
        `get_last_message() -> String`

        wrapper for _state access
        """
        function get_last_message() ::String
            return _state[]._last_message
        end

        """
        `get_last_exception() -> Exception`

        wrapper for _state access
        """
        function get_last_exception() ::Exception
            return _state[]._last_exception
        end
    end

    """
    offers julia-side memory management for C++ jluna
    """
    module memory_handler

        _current_id = UInt64(0);
        const _refs = Ref(Dict{UInt64, Base.RefValue{Any}}())
        const _ref_counter = Ref(IdDict{UInt64, UInt64}())

        const _ref_id_marker = '#'

        """
        print_refs() -> Nothing

        pretty print _ref state, for debugging
        """
        function print_refs() ::Nothing

            println("jluna.memory_handler._refs: ");
            for e in _refs[]
                println("\t", Int64(e.first), " => ", e.second[], " (", typeof(e.second[]), ")")
            end
        end

        """
        create_reference(::UInt64, ::Any) -> UInt64

        add reference to _refs
        """
        function create_reference(to_wrap::Any) ::UInt64

            if (to_wrap == nothing)
                return 0;
            end

            global _current_id += 1;
            key = _current_id;

            #println("[JULIA] allocated " * string(key) * " (" * Base.string(to_wrap) * ")")

            if (haskey(_refs[], key))
                @assert _refs[][key].x == to_wrap && typeof(to_wrap) == typeof(_refs[][key].x)
                _ref_counter[][key] += 1
            else
                _refs[][key] = Base.RefValue{Any}(to_wrap)
                _ref_counter[][key] = 1
            end

            return key;
        end

        """
        set_reference(::UInt64, ::T) -> Nothing

        update the value of a reference in _refs without adding a new entry or changing it's key, ref pointers C++ side stay valid
        """
        function set_reference(key::UInt64, new_value::T) ::Base.RefValue{Any} where T

            _refs[][key] = Base.RefValue{Any}(new_value)
            return _refs[][key]
        end

        """
        """
        function assign(new_value::T, names::Symbol...) ::T where T

            unnamed_to_index(s::Symbol) = tryparse(UInt64, chop(string(s), head = 1, tail = 0))

            name = "";

            in_main = false;

            for n in names

                as_string = string(n);
                if as_string[1] == _ref_id_marker
                    if as_string[2] == '1' && length(as_string) == 2 # main
                        in_main = true
                        continue
                    else
                        name *= "jluna.memory_handler._refs[][" * chop(string(n), head = 1, tail = 0) * "][]"
                    end
                elseif as_string[1] == '['
                    name *= string(n)
                else
                    name *= "." * string(n)
                end
            end

            if in_main
                name = chop(name, head = 1, tail = 0)   # remove first .
            end

            Main.eval(:($(Meta.parse(name)) = $new_value));
            return new_value;
        end

        """
        """
        function evaluate(names::Symbol...) ::Any

            name = "";

            for n in names

                as_string = string(n);
                if as_string[1] == _ref_id_marker
                    name *= "jluna.memory_handler._refs[][" * chop(string(n), head = 1, tail = 0) * "][]"
                elseif as_string[1] == '['
                    name *= string(n)
                else
                    name *= "." * string(n)
                end
            end

            return Main.eval(:($(Meta.parse(name))))
        end

        """
        get_reference(::Int64) -> Any
        """
        function get_reference(key::UInt64) ::Any

            if (key == 0)
                return nothing
            end

           return _refs[][key]
        end

        """
        free_reference(::UInt64) -> Nothing

        free reference from _refs
        """
        function free_reference(key::UInt64) ::Nothing

            if (key == 0)
                return nothing;
            end

            @assert haskey(_refs[], key)
            #println("[JULIA] freed " * string(key) * " (" * Base.string(typeof(_refs[][key].x)) * ")")

            global _ref_counter[][key] -= 1
            count = _ref_counter[][key]

            if (count == 0)
                delete!(_ref_counter[], key)
                delete!(_refs[], key)
            end

            return nothing;
        end

        """
        force_free() -> Nothing

        immediately deallocate all C++-managed values
        """
        function force_free() ::Nothing

            for k in keys(_refs)
                delete!(_refs[], k)
                delete!(_ref_counter[], k)
            end

            @assert isempty(_refs) && isempty(_ref_counter)

            return nothing;
        end
    end
end