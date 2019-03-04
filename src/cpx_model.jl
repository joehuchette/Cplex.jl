mutable struct Model
    env::Env # Cplex environment
    lp::Ptr{Cvoid} # Cplex problem (lp)
    has_int::Bool # problem has integer variables?
    has_qc::Bool # problem has quadratic constraints?
    has_sos::Bool # problem has Special Ordered Sets?
    callback::Any
    terminator::Vector{Cint}
end
function Model(env::Env, lp::Ptr{Cvoid})
    notify_new_model(env)
    model = Model(env, lp, false, false, false, nothing, Cint[0])
    function model_finalizer(model)
        free_problem(model)
        notify_freed_model(env)
    end
    @compat finalizer(model_finalizer, model)
    set_terminate(model)
    return model
end

function Model(env::Env, name::String="CPLEX.jl")
    @assert is_valid(env)
    stat = Vector{Cint}(undef, 1)
    tmp = @cpx_ccall(createprob, Ptr{Cvoid}, (Ptr{Cvoid}, Ptr{Cint}, Ptr{Cchar}), env.ptr, stat, name)
    if tmp == C_NULL
        throw(CplexError(env, stat))
    end
    return Model(env, tmp)
end

function read_model(model::Model, filename::String)
    stat = @cpx_ccall(readcopyprob, Cint, (Ptr{Cvoid}, Ptr{Cvoid}, Ptr{Cchar}, Ptr{Cchar}), model.env.ptr, model.lp, filename, C_NULL)
    if stat != 0
        throw(CplexError(model.env, stat))
    end
    prob_type = get_prob_type(model)
    if prob_type in [:MILP,:MIQP, :MIQCP]
        model.has_int = true
    end
    if prob_type in [:QP, :MIQP, :QCP, :MIQCP]
        model.has_qc = true
    end
end

function write_model(model::Model, filename::String)
    if endswith(filename,".mps")
        filetype = "MPS"
    elseif endswith(filename,".lp")
        filetype = "LP"
    else
        error("Unrecognized file extension: $filename (Only .mps and .lp are supported)")
    end
    stat = @cpx_ccall(writeprob, Cint, (Ptr{Cvoid}, Ptr{Cvoid}, Ptr{Cchar}, Ptr{Cchar}), model.env.ptr, model.lp, filename, filetype)
    if stat != 0
        throw(CplexError(model.env, stat))
    end
end

## TODO: deep copy model, reset model

function c_api_getobjsen(model::Model)
    sense_int = @cpx_ccall(getobjsen, Cint, (
                           Ptr{Cvoid},
                           Ptr{Cvoid},
                           ),
                           model.env.ptr, model.lp)

    return sense_int
end
function get_sense(model::Model)
    sense_int = c_api_getobjsen(model)
    if sense_int == 1
        return :Min
    elseif sense_int == -1
        return :Max
    else
        error("CPLEX: problem object or environment does not exist")
    end
end

function set_sense!(model::Model, sense)
    if sense == :Min
        @cpx_ccall(chgobjsen, Nothing, (Ptr{Cvoid}, Ptr{Cvoid}, Cint), model.env.ptr, model.lp, 1)
    elseif sense == :Max
        @cpx_ccall(chgobjsen, Nothing, (Ptr{Cvoid}, Ptr{Cvoid}, Cint), model.env.ptr, model.lp, -1)
    else
        error("Unrecognized objective sense $sense")
    end
end

function c_api_chgobjsen(model::Model, sense_int::Cint)
    @cpx_ccall(chgobjsen, Nothing, (Ptr{Cvoid}, Ptr{Cvoid}, Cint),
               model.env.ptr, model.lp, sense_int)
end

function c_api_getobj(model::Model, sized_obj::FVec,
                      col_start::Cint, col_end::Cint)

    nvars = num_var(model)
    stat = @cpx_ccall(getobj, Cint, (
                      Ptr{Cvoid},
                      Ptr{Cvoid},
                      Ptr{Cdouble},
                      Cint,
                      Cint
                      ),
                      model.env.ptr, model.lp, sized_obj,
                      col_start - Cint(1), col_end - Cint(1))
    if stat != 0
        throw(CplexError(model.env, stat))
    end
end

function get_obj(model::Model)
    nvars = num_var(model)
    obj = Vector{Cdouble}(undef, nvars)
    stat = @cpx_ccall(getobj, Cint, (
                      Ptr{Cvoid},
                      Ptr{Cvoid},
                      Ptr{Cdouble},
                      Cint,
                      Cint
                      ),
                      model.env.ptr, model.lp, obj, 0, nvars-1)
    if stat != 0
        throw(CplexError(model.env, stat))
    end
    return obj
end

const type_map = Dict(
     0 => :LP,
     1 => :MILP,
     3 => :FIXEDMILP, # actually fixed milp
     5 => :QP,
     7 => :MIQP,
     8 => :FIXEDMIQP,
    10 => :QCP,
    11 => :MIQCP
)

const rev_prob_type_map = Dict(
    :LP    => 0,
    :MILP  => 1,
    :FIXEDMILP  => 3,
    :QP    => 5,
    :MIQP  => 7,
    :FIXEDMIQP  => 8,
    :QCP   => 10,
    :MIQCP => 11
)

function get_prob_type(model::Model)
  ret = @cpx_ccall(getprobtype, Cint, (
                   Ptr{Cvoid},
                   Ptr{Cvoid}),
                   model.env.ptr, model.lp)
  ret == -1 && error("No problem of environment")
  return type_map[Int(ret)]
end

@deprecate set_prob_type! c_api_chgprobtype

function c_api_chgprobtype(model::Model, tyint::Int)
    stat = @cpx_ccall(chgprobtype, Cint, (
                     Ptr{Cvoid},
                     Ptr{Cvoid},
                     Cint),
                     model.env.ptr, model.lp, tyint)
    if stat != 0
        throw(CplexError(model.env, stat))
    end
    model.has_int = false
    model.has_qc = false
    if type_map[tyint] in [:MILP,:MIQP, :MIQCP]
        model.has_int = true
    end
    if type_map[tyint] in [:QP, :MIQP, :QCP, :MIQCP]
        model.has_qc = true
    end
end
c_api_chgprobtype(model::Model, ty::Symbol) = c_api_chgprobtype(model, rev_prob_type_map[ty])


function set_obj!(model::Model, c::Vector)
    nvars = num_var(model)
    stat = @cpx_ccall(chgobj, Cint, (
                        Ptr{Cvoid},
                        Ptr{Cvoid},
                        Cint,
                        Ptr{Cint},
                        Ptr{Cdouble}
                        ),
                        model.env.ptr, model.lp, nvars, Cint[0:nvars-1;], float(c))
    if stat != 0
        throw(CplexError(model.env, stat))
    end
end

function c_api_chgobj(model::Model, indices::IVec, values::FVec)
    nvars = length(indices)
    stat = @cpx_ccall(chgobj, Cint, (
                        Ptr{Cvoid},
                        Ptr{Cvoid},
                        Cint,
                        Ptr{Cint},
                        Ptr{Cdouble}
                        ),
                        model.env.ptr, model.lp, nvars,
                        indices .- Cint(1), values)
    if stat != 0
        throw(CplexError(model.env, stat))
    end
end

@deprecate set_warm_start! c_api_addmipstarts

c_api_addmipstarts(model::Model, x::Vector{Float64}, effortlevel::Integer = CPX_MIPSTART_AUTO) = c_api_addmipstarts(model, Cint[1:length(x);], x, effortlevel)

function c_api_addmipstarts(model::Model, indx::IVec, val::FVec, effortlevel::Integer)
    stat = @cpx_ccall(addmipstarts, Cint, (
                      Ptr{Cvoid},
                      Ptr{Cvoid},
                      Cint,
                      Cint,
                      Ptr{Cint},
                      Ptr{Cint},
                      Ptr{Cdouble},
                      Ptr{Cint},
                      Ptr{Ptr{Cchar}}
                      ),
                      model.env.ptr, model.lp, 1, length(indx), Cint[0], indx .- Cint(1), val, Cint[effortlevel], C_NULL)
    if stat != 0
        throw(CplexError(model.env, stat))
    end
end

c_api_chgmipstarts(model::CPLEX.Model, x::Vector{Float64}, effortlevel::Integer = CPX_MIPSTART_AUTO) = c_api_chgmipstarts(model, Cint[1:length(x);], x, effortlevel)

function c_api_chgmipstarts(model::CPLEX.Model, indx::IVec, val::FVec, effortlevel::Integer)
    stat = @cpx_ccall(chgmipstarts, Cint, (
                      Ptr{Cvoid},
                      Ptr{Cvoid},
                      Cint,
                      Ptr{Cint},
                      Cint,
                      Ptr{Cint},
                      Ptr{Cint},
                      Ptr{Cdouble},
                      Ptr{Cint},
                      Ptr{Ptr{Cchar}}
                      ),
                      model.env.ptr, model.lp, 1, Cint[0], length(indx), Cint[0], indx .- Cint(1), val, Cint[effortlevel], C_NULL)
    if stat != 0
        throw(CplexError(model.env, stat))
    end
end

function free_problem(model::Model)
    tmp = Ptr{Cvoid}[model.lp]
    stat = @cpx_ccall(freeprob, Cint, (Ptr{Cvoid}, Ptr{Cvoid}), model.env.ptr, tmp)
    if stat != 0
        throw(CplexError(model.env, stat))
    end
end

function set_terminate(model::Model)
    stat = @cpx_ccall(setterminate, Cint, (Ptr{Cvoid},Ptr{Cint}), model.env.ptr, model.terminator)
    if stat != 0
        throw(CplexError(env, stat))
    end
end

terminate(model::Model) = (model.terminator[1] = 1)
