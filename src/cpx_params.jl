# const CPX_INFBOUND = 1e20
# const CPX_STR_PARAM_MAX = 512
const PARAM_TYPES = Dict{Int, DataType}(
    0 => Void,
    1 => Cint,
    2 => Cdouble,
    3 => Cchar,
    4 => Clonglong
)
function get_param_type(env::Env, indx::Int)
    ptype = Vector{Cint}(1)
    @cpx_ccall_error(env, getparamtype, Cint, (Ptr{Void}, Cint, Ptr{Cint}),
        env.ptr, convert(Cint,indx), ptype)
    if haskey(PARAM_TYPES, ptype[1])
        return PARAM_TYPES[ptype[1]]
    else
        error("Parameter type not recognized")
    end
end
get_param_type(env::Env, name::String) = get_param_type(env, paramName2Indx[name])

function getparam(::Type{Cint}, env::Env, pindx::Cint)
    ret = Vector{Cint}(1)
    @cpx_ccall_error(env, getintparam, Cint, (Ptr{Void}, Cint, Ptr{Cint}), env.ptr, pindx, ret)
    return ret[1]
end
function getparam(::Type{Cdouble}, env::Env, pindx::Cint)
    ret = Vector{Cdouble}(1)
    @cpx_ccall_error(env, getdblparam, Cint, (Ptr{Void}, Cint, Ptr{Cint}), env.ptr, pindx, ret)
    return ret[1]
end
function getparam(::Type{Clonglong}, env::Env, pindx::Cint)
    ret = Vector{Clonglong}(1)
    @cpx_ccall_error(env, getlongparam, Cint, (Ptr{Void}, Cint, Ptr{Clonglong}), env.ptr, pindx, ret)
    return ret[1]
end
function getparam(::Type{Cchar}, env::Env, pindx::Cint)
    ret = Vector{Cchar}(CPX_STR_PARAM_MAX)
    @cpx_ccall_error(env, getstrparam, Cint, (Ptr{Void}, Cint, Ptr{Cchar}), env.ptr, pindx, ret)
    return bytestring(pointer(ret))
end
getparam(T, env::Env, pindx::Cint) = warn("Trying to get a parameter of unknown type; doing nothing.")
get_param(env::Env, pindx::Int) = get_param(get_param_type(env, pindx), env, convert(Cint, pindx))
get_param(env::Env, pname::String) = get_param(env, paramName2Indx[pname])


function set_param!(::Type{Cint}, env::Env, pindx::Cint, val)
    @cpx_ccall_error(env, setintparam, Cint, (Ptr{Void}, Cint, Cint), env.ptr, pindx, convert(Cint, val))
end
function set_param!(::Type{Cdouble}, env::Env, pindx::Cint, val)
    @cpx_ccall_error(env, getdblparam, Cint, (Ptr{Void}, Cint, Cdouble), env.ptr, pindx, float(val))
end
function set_param!(::Type{Clonglong}, env::Env, pindx::Cint, val)
    @cpx_ccall_error(env, getlongparam, Cint, (Ptr{Void}, Cint, Clonglong), env.ptr, pindx, convert(Clonglong, val))
end
function set_param!(::Type{Cchar}, env::Env, pindx::Int, val)
    @cpx_ccall_error(env, getstrparam, Cint, (Ptr{Void}, Cint, Cstring), env.ptr, pindx, String(val))
end
set_param!(T, env::Env, pindx::Cint, val) = warn("Trying to set a parameter of unknown type; doing nothing.")
set_param!(env::Env, pindx::Int, val) = set_param!(get_param_type(env, pindx), env, convert(Cint, pindx), val)
set_param!(env::Env, pname::String, val) = set_param!(env, paramName2Indx[pname], val)




# tune_param(model::Model) = tune_param(model, Dict(), Dict(), Dict())
#
# function tune_param(model::Model, intfixed::Dict, dblfixed::Dict, strfixed::Dict)
#   intkeys = Cint[k for k in keys(intfixed)]
#   dblkeys = Cint[k for k in keys(dblfixed)]
#   strkeys = Cint[k for k in keys(strfixed)]
#   tune_stat = Vector{Cint}(1)
#   stat = @cpx_ccall(tuneparam, Cint, (Ptr{Void},
#                          Ptr{Void},
#                          Cint,
#                          Ptr{Cint},
#                          Ptr{Cint},
#                          Cint,
#                          Ptr{Cint},
#                          Ptr{Cdouble},
#                          Cint,
#                          Ptr{Cint},
#                          Ptr{Ptr{Cchar}},
#                          Ptr{Cint}),
#                         model.env,
#                         model.lp,
#                         convert(Cint, length(intkeys)),
#                         intkeys,
#                         Cint[intfixed[int(k)] for k in intkeys],
#                         convert(Cint, length(dblkeys)),
#                         dblkeys,
#                         Cdouble[dblfixed[int(k)] for k in dblkeys],
#                         convert(Cint, length(strkeys)),
#                         strkeys,
#                         [strkeys[int(k)] for k in strkeys],
#                         tune_stat)
#   if stat != 0
#     throw(CplexError(model.env, stat))
#   end
#   for param in keys(paramName2Indx)
#     print(param * ": ")
#     val = get_param(model.env, param)
#     println(val)
#   end
#   return tune_stat[1]
# end
