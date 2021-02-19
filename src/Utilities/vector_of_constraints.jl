## Storage of constraints
#
# All `F`-in-`S` constraints are stored in a vector of `ConstraintEntry{F, S}`.
# The index in this vector of a constraint of index
# `ci::MOI.ConstraintIndex{F, S}` is given by `model.constrmap[ci.value]`. The
# advantage of this representation is that it does not require any dictionary
# hence it never needs to compute a hash.
#
# It may seem redundant to store the constraint index `ci` as well as the
# function and sets in the tuple but it is used to efficiently implement the
# getter for `MOI.ListOfConstraintIndices{F, S}`. It is also used to implement
# `MOI.delete`. Indeed, when a constraint is deleted, it is removed from the
# vector hence the index in the vector of all the functions that were stored
# after must be decreased by one. As the constraint index is stored in the
# vector, it readily gives the entries of `model.constrmap` that need to be
# updated.

struct VectorOfConstraints{F,S} <: MOI.ModelLike
    constraints::CleverDicts.CleverDict{MOI.ConstraintIndex{F,S},Tuple{F,S},typeof(CleverDicts.key_to_index),typeof(CleverDicts.index_to_key)}
end

function MOI.add_constraint(v::VectorOfConstraints{F,S}, func::F, set::S) where {F,S}
    return CleverDicts.add_item(v.constraints, (F, S))
end
function MOI.delete(v::VectorOfConstraints{F,S}, ci::MOI.ConstraintIndex{F,S}) where {F,S}
    MOI.throw_if_not_valid(v, ci)
    delete!(v.constraints, ci)
end
function MOI.get(v::VectorOfConstraints{F,S}, ::MOI.ConstraintFunction, ci::MOI.ConstraintIndex{F,S}) where {F,S}
    return v.constraints[ci][1]
end
function MOI.get(v::VectorOfConstraints{F,S}, ::MOI.ConstraintSet, ci::MOI.ConstraintIndex{F,S}) where {F,S}
    return v.constraints[ci][2]
end

function MOI.get(
    v::VectorOfConstraints{F,S},
    ::MOI.ListOfConstraints
)::Vector{Tuple{DataType,DataType}} where {F,S}
    return isempty(v.constraints) ? [] : [(F, S)]
end
function MOI.get(v::VectorOfConstraints{F,S}, ::MOI.NumberOfConstraints{F,S}) where {F,S}
    return length(v.constraints)
end
function MOI.get(v::VectorOfConstraints{F,S}, ci::MOI.ListOfConstraintIndices{F,S}) where {F,S}
    return keys(v.constraints)
end
function MOI.modify(
    v::VectorOfConstraints{F,S},
    ci::MOI.ConstraintIndex{F,S},
    change::MOI.AbstractFunctionModification,
) where {F,S}
    func, set = constraint[ci]
    constraint[ci] = (modify_function(func, change), set)
    return
end

function _remove_variable(v::VectorOfConstraints, vi::MOI.VariableIndex)
    map_values(v.constraints) do func_set
        remove_variable(func_set..., vi)
    end
end
function _filter_variables(keep::Function, v::VectorOfConstraints)
    map_values(v.constraints) do func_set
        filter_variables(kepp, func_set...)
    end
end

function _vector_of_variables_with(::VectorOfConstraints, ::Union{MOI.VariableIndex,Vector{MOI.VariableIndex}})
    return MOI.ConstraintIndex{MOI.VectorOfVariables}[]
end
function throw_delete_variable_in_vov(vi::MOI.VariableIndex)
    message = string(
        "Cannot delete variable as it is constrained with other",
        " variables in a `MOI.VectorOfVariables`.",
    )
    return throw(MOI.DeleteNotAllowed(vi, message))
end
function _vector_of_variables_with(
    v::VectorOfConstraints{MOI.VectorOfVariables},
    vi::MOI.VariableIndex,
)
    rm = MOI.ConstraintIndex{MOI.VectorOfVariables}[]
    for (f, s) in values(v)
        if vi in f.variables
            if length(f.variables) > 1
                # If `supports_dimension_update(s)` then the variable will be
                # removed in `_remove_variable`.
                if !MOI.supports_dimension_update(typeof(s))
                    throw_delete_variable_in_vov(vi)
                end
            else
                push!(rm, ci)
            end
        end
    end
    return rm
end
function _vector_of_variables_with(
    v::VectorOfConstraints{MOI.VectorOfVariables},
    vis::Vector{MOI.VariableIndex},
)
    rm = MOI.ConstraintIndex{MOI.VectorOfVariables}[]
    for (f, s) in values(v)
        if vis == f.variables
            push!(rm, ci)
        end
    end
    return rm
end
