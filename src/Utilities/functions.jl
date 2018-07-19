using Compat
using Compat.Test

"""
    evalvariables(varval::Function, f::AbstractFunction)

Returns the value of function `f` if each variable index `vi` is evaluated as `varval(vi)`.
"""
function evalvariables end
evalvariables(varval::Function, f::SVF) = varval(f.variable)
evalvariables(varval::Function, f::VVF) = varval.(f.variables)
function evalvariables(varval::Function, f::SAF)
    if VERSION >= v"0.7-"
        return mapreduce(t->evalterm(varval, t), +, f.terms, init=f.constant)
    else
        return mapreduce(t->evalterm(varval, t), +, f.constant, f.terms)
    end
end
function evalvariables(varval::Function, f::VAF)
    out = copy(f.constants)
    for t in f.terms
        out[t.output_index] += evalterm(varval, t.scalar_term)
    end
    out
end
function evalvariables(varval::Function, f::SQF)
    init = zero(f.constant)
    if VERSION >= v"0.7-"
        lin = mapreduce(t->evalterm(varval, t), +, f.affine_terms, init=init)
        quad = mapreduce(t->evalterm(varval, t), +, f.quadratic_terms, init=init)
    else
        lin = mapreduce(t->evalterm(varval, t), +, init, f.affine_terms)
        quad = mapreduce(t->evalterm(varval, t), +, init, f.quadratic_terms)
    end
    return lin + quad + f.constant
end
function evalvariables(varval::Function, f::VQF)
    out = copy(f.constants)
    for t in f.affine_terms
        out[t.output_index] += evalterm(varval, t.scalar_term)
    end
    for t in f.quadratic_terms
        out[t.output_index] += evalterm(varval, t.scalar_term)
    end
    out
end
# Affine term
function evalterm(varval::Function, t::SAT)
    return t.coefficient * varval(t.variable_index)
end
# Quadratic term
function evalterm(varval::Function, t::SQT)
    tval = t.coefficient * varval(t.variable_index_1) * varval(t.variable_index_2)
    t.variable_index_1 == t.variable_index_2 ? tval/2 : tval
end

function mapvariable(varmap::Function, t::SAT)
    return SAT(t.coefficient, varmap(t.variable_index))
end
function mapvariable(varmap::Function, t::VAT)
    return VAT(t.output_index, mapvariable(varmap, t.scalar_term))
end
function mapvariable(varmap::Function, t::SQT)
    inds = varmap.((t.variable_index_1, t.variable_index_2))
    return SQT(t.coefficient, inds...)
end
function mapvariable(varmap::Function, t::VQT)
    VQT(t.output_index, mapvariable(varmap, t.scalar_term))
end
function mapvariables(varmap::Function, f::SVF)
    return SVF(varmap(f.variable))
end
function mapvariables(varmap::Function, f::VVF)
    return VVF(varmap.(f.variables))
end
function mapvariables(varmap::Function, f::Union{SAF, VAF})
    typeof(f)(mapvariable.(varmap, f.terms), _constant(f))
end
function mapvariables(varmap::Function, f::Union{SQF, VQF})
    lin = mapvariable.(varmap, f.affine_terms)
    quad = mapvariable.(varmap, f.quadratic_terms)
    return typeof(f)(lin, quad, _constant(f))
end
mapvariables(varmap, f::MOI.AbstractFunction) = mapvariables(vi -> varmap[vi], f)
mapvariables(varmap::Function, change::Union{SConstC, VConstC}) = change
function mapvariables(varmap::Function, change::SCoeffC)
    return SCoeffC(varmap(change.variable), change.new_coefficient)
end
function mapvariables(varmap::Function, change::MulC)
    return MulC(varmap(change.variable), change.new_coefficients)
end
function mapvariables(varmap, f::MOI.AbstractFunctionModification)
    return mapvariables(vi -> varmap[vi], f)
end

# Cat for MOI sets
_constant(f::Union{SAF, SQF}) = f.constant
_constant(f::Union{VAF, VQF}) = f.constants
constant(f::Union{SAF, SQF}) = [f.constant]
constant(f::Union{VAF, VQF}) = f.constants
offsetterm(t::SAT, offset::Int) = VAT(offset+1, t)
offsetterm(t::VAT, offset::Int) = VAT(offset+t.output_index, t.scalar_term)
offsetterms(f::Union{SAF, VAF}, offset::Int) = offsetterm.(f.terms, offset)
function moivcat(f::Union{SAF, VAF}...)
    n = length(f)
    offsets = cumsum(collect(MOI.output_dimension.(f)))
    offsets = [0; offsets[1:(n-1)]]
    terms = vcat((offsetterms.(f, offsets))...)
    cst = vcat(constant.(f)...)
    VAF(terms, cst)
end

# Define conversion SingleVariable -> ScalarAffineFunction and VectorOfVariable -> VectorAffineFunction{T}
function SAF{T}(f::SVF) where T
    SAF([SAT(one(T), f.variable)], zero(T))
end
function VAF{T}(f::VVF) where T
    n = length(f.variables)
    return VAF(map(i -> VAT(i, SAT(one(T), f.variables[i])), 1:n), zeros(T, n))
end

# Implements iterator interface
struct ScalarFunctionIterator{F<:MOI.AbstractVectorFunction}
    f::F
end
eachscalar(f::MOI.AbstractVectorFunction) = ScalarFunctionIterator(f)
Base.start(it::ScalarFunctionIterator) = 1
Base.done(it::ScalarFunctionIterator, state) = state > length(it)
Base.next(it::ScalarFunctionIterator, state) = (it[state], state+1)
function Base.length(it::ScalarFunctionIterator{<:MOI.AbstractVectorFunction})
    return MOI.output_dimension(it.f)
end
Base.eltype(it::ScalarFunctionIterator{VVF}) = SVF
Base.eltype(it::ScalarFunctionIterator{VAF{T}}) where T = SAF{T}
Base.eltype(it::ScalarFunctionIterator{VQF{T}}) where T = SQF{T}
Compat.lastindex(it::ScalarFunctionIterator) = length(it)

# Define getindex for Vector functions

function Base.getindex(it::ScalarFunctionIterator{VVF}, i::Integer)
    return SVF(it.f.variables[i])
end
# Returns the scalar terms of output_index i
function scalar_terms_at_index(terms::Vector{<:Union{VAT, VQT}}, i::Int)
    I = findall(t -> t.output_index == i, terms)
    map(i -> terms[i].scalar_term, I)
end
function Base.getindex(it::ScalarFunctionIterator{<:VAF}, i::Integer)
    SAF(scalar_terms_at_index(it.f.terms, i), it.f.constants[i])
end
function Base.getindex(it::ScalarFunctionIterator{<:VQF}, i::Integer)
    lin = scalar_terms_at_index(it.f.affine_terms, i)
    quad = scalar_terms_at_index(it.f.quadratic_terms, i)
    return SQF(lin, quad, it.f.constants[i])
end

function Base.getindex(it::ScalarFunctionIterator{VAF{T}}, I::AbstractVector) where T
    terms = VAT{T}[]
    constant = Vector{T}(undef, length(I))
    for (i, j) in enumerate(I)
        g = it[j]
        append!(terms, map(t -> VAT(i, t), g.terms))
        constant[i] = g.constant
    end
    VAF(terms, constant)
end

"""
    termindices(t::Union{ScalarAffineTerm, VectorAffineTerm})

Returns the indices of the input term `t` as a tuple of `Int`s. For `t::ScalarAffineTerm`, this is a 1-tuple of the variable index. For `t::VectorAffineTerm`, this is a 2-tuple of the row/output and variable indices of the term.
"""
termindices(t::SAT) = (t.variable_index.value,)
termindices(t::VAT) = (t.output_index, termindices(t.scalar_term)...)

"""
    unsafe_add(t1::ScalarAffineTerm, t2::ScalarAffineTerm)

Sums the coefficients of `t1` and `t2` and returns an output `ScalarAffineTerm`. It is unsafe because it uses the `variable_index` of `t1` as the `variable_index` of the output without checking that it is equal to that of `t2`.
"""
function unsafe_add(t1::SAT, t2::SAT)
    return SAT(t1.coefficient + t2.coefficient, t1.variable_index)
end

"""
    unsafe_add(t1::VectorAffineTerm, t2::VectorAffineTerm)

Sums the coefficients of `t1` and `t2` and returns an output `VectorAffineTerm`. It is unsafe because it uses the `output_index` and `variable_index` of `t1` as the `output_index` and `variable_index` of the output term without checking that they are equal to those of `t2`.
"""
function unsafe_add(t1::VAT, t2::VAT)
    coefficient = t1.scalar_term.coefficient + t2.scalar_term.coefficient
    scalar_term = SAT(coefficient, t1.scalar_term.variable_index)
    return VAT(t1.output_index, scalar_term)
end

"""
    coefficient(t::Union{ScalarAffineTerm, VectorAffineTerm})

Finds the coefficient associated with the term `t`.
"""
coefficient(t::SAT) = t.coefficient
coefficient(t::VAT) = t.scalar_term.coefficient

"""
    canonical(f::AbstractFunction)

Returns the function in a canonical form, i.e.
* A term appear only once.
* The coefficients are nonzero.
* The terms appear in increasing order of variable where there the order of the variables is the order of their value.
* For a `AbstractVectorFunction`, the terms are sorted in ascending order of output index.

### Examples
If `x` (resp. `y`, `z`) is `VariableIndex(1)` (resp. 2, 3).
The canonical representation of `ScalarAffineFunction([y, x, z, x, z], [2, 1, 3, -2, -3], 5)` is `ScalarAffineFunction([x, y], [-1, 2], 5)`.

"""
function canonical(f::Union{SAF, VAF})
    sorted_terms = sort(f.terms, by = termindices)
    terms = eltype(f.terms)[]
    for t in sorted_terms
        tnot0 = !iszero(coefficient(t))
        if !isempty(terms) && termindices(t) == termindices(last(terms)) && tnot0
            terms[end] = unsafe_add(t, last(terms))
        elseif tnot0
            if !isempty(terms) && iszero(coefficient(last(terms)))
                terms[end] = t
            else
                push!(terms, t)
            end
        end
    end
    if !isempty(terms) && iszero(coefficient(last(terms)))
        pop!(terms)
    end
    typeof(f)(terms, _constant(f))
end

function test_variablenames_equal(model, variablenames)
    seen_name = Dict(name => false for name in variablenames)
    for index in MOI.get(model, MOI.ListOfVariableIndices())
        vname = MOI.get(model, MOI.VariableName(), index)
        if !haskey(seen_name, vname)
            error("Variable with name $vname present in model but not expected list of variable names.")
        end
        if seen_name[vname]
            error("Variable with name $vname present twice in model (shouldn't happen!)")
        end
        seen_name[vname] = true
    end
    for (vname,seen) in seen_name
        if !seen
            error("Did not find variable with name $vname in intance.")
        end
    end
end
function test_constraintnames_equal(model, constraintnames)
    seen_name = Dict(name => false for name in constraintnames)
    for (F,S) in MOI.get(model, MOI.ListOfConstraints())
        for index in MOI.get(model, MOI.ListOfConstraintIndices{F,S}())
            cname = MOI.get(model, MOI.ConstraintName(), index)
            if !haskey(seen_name, cname)
                error("Constraint with name $cname present in model but not expected list of constraint names.")
            end
            if seen_name[cname]
                error("Constraint with name $cname present twice in model (shouldn't happen!)")
            end
            seen_name[cname] = true
        end
    end
    for (cname,seen) in seen_name
        if !seen
            error("Did not find constraint with name $cname in intance.")
        end
    end
end

"""
    test_models_equal(model1::ModelLike, model2::ModelLike, variablenames::Vector{String}, constraintnames::Vector{String})

Test that `model1` and `model2` are identical using `variablenames` as as keys for the variable names and `constraintnames` as keys for the constraint names. Uses `Base.Test` macros.
"""
function test_models_equal(model1::MOI.ModelLike, model2::MOI.ModelLike, variablenames::Vector{String}, constraintnames::Vector{String})
    # TODO: give test-friendly feedback instead of errors?
    test_variablenames_equal(model1, variablenames)
    test_variablenames_equal(model2, variablenames)
    test_constraintnames_equal(model1, constraintnames)
    test_constraintnames_equal(model2, constraintnames)

    variablemap_2to1 = Dict{VI,VI}()
    for vname in variablenames
        index1 = MOI.get(model1, VI, vname)
        index2 = MOI.get(model2, VI, vname)
        variablemap_2to1[index2] = index1
    end

    for cname in constraintnames
        index1 = MOI.get(model1, CI, cname)
        index2 = MOI.get(model2, CI, cname)
        f1 = MOI.get(model1, MOI.ConstraintFunction(), index1)
        f2 = MOI.get(model2, MOI.ConstraintFunction(), index2)
        s1 = MOI.get(model1, MOI.ConstraintSet(), index1)
        s2 = MOI.get(model2, MOI.ConstraintSet(), index2)
        @test isapprox(f1, mapvariables(variablemap_2to1, f2))
        @test s1 == s2
    end
    attrs1 = MOI.get(model1, MOI.ListOfModelAttributesSet())
    attrs2 = MOI.get(model2, MOI.ListOfModelAttributesSet())
    attr_list = attrs1 ∪ attrs2
    for attr in attr_list 
        @test MOI.canget(model1, attr)
        value1 = MOI.get(model1, attr)
        @test MOI.canget(model2, attr)
        value2 = MOI.get(model2, attr)
        if value1 isa MOI.AbstractFunction
            @test value2 isa MOI.AbstractFunction
            @test isapprox(value1, attribute_value_map(variablemap_2to1, value2))
        else
            @test !(value2 isa MOI.AbstractFunction)
            @test value1 == value2
        end
    end
end


_hasvar(v::VI, vi::VI) = v == vi
_hasvar(t::SAT, vi::VI) = t.variable_index == vi
_hasvar(t::SQT, vi::VI) = t.variable_index_1 == vi || t.variable_index_2 == vi
_hasvar(t::Union{VAT, VQT}, vi::VI) = _hasvar(t.scalar_term, vi)
# Removes terms or variables in `vis_or_terms` that contains the variable of index `vi`
function _rmvar(vis_or_terms::Vector, vi::VI)
    return vis_or_terms[.!_hasvar.(vis_or_terms, Ref(vi))]
end

"""
    removevariable(f::AbstractFunction, vi::VariableIndex)

Return a new function `f` with the variable vi removed.
"""
function removevariable(f::VVF, vi)
    VVF(_rmvar(f.variables, vi))
end
function removevariable(f::Union{SAF, VAF}, vi)
    typeof(f)(_rmvar(f.terms, vi), _constant(f))
end
function removevariable(f::Union{SQF, VQF}, vi)
    terms = _rmvar.((f.affine_terms, f.quadratic_terms), Ref(vi))
    typeof(f)(terms..., _constant(f))
end

"""
    modifyfunction(f::AbstractFunction, change::AbstractFunctionModification)

Return a new function `f` modified according to `change`.
"""
function modifyfunction(f::SAF, change::SConstC)
    return SAF(f.terms, change.new_constant)
end
function modifyfunction(f::VAF, change::VConstC)
    return VAF(f.terms, change.new_constant)
end
function modifyfunction(f::SQF, change::SConstC)
    return SQF(f.affine_terms, f.quadratic_terms, change.new_constant)
end
function modifyfunction(f::VQF, change::VConstC)
    return VQF(f.affine_terms, f.quadratic_terms, change.new_constant)
end
function _modifycoefficient(terms::Vector{<:SAT}, variable::VI, new_coefficient)
    terms = copy(terms)
    i = something(findfirst(t -> _hasvar(t, variable), terms), 0)
    if iszero(i)
        # The variable was not already in the function
        if !iszero(new_coefficient)
            push!(terms, SAT(new_coefficient, variable))
        end
    else
        # The variable was already in the function
        if iszero(new_coefficient)
            deleteat!(terms, i)
        else
            terms[i] = SAT(new_coefficient, variable)
        end
    end
    terms
end
function modifyfunction(f::SAF, change::SCoeffC)
    lin = _modifycoefficient(f.terms, change.variable, change.new_coefficient)
    return SAF(lin, f.constant)
end
function modifyfunction(f::SQF, change::SCoeffC)
    lin = _modifycoefficient(f.affine_terms, change.variable, change.new_coefficient)
    return SQF(lin, f.quadratic_terms, f.constant)
end
function _modifycoefficients(n, terms::Vector{<:VAT}, variable::VI, new_coefficients)
    terms = copy(terms)
    # Maps between rows in the `VectorAffineTerm`s and indices in new_coefficients
    rowmap = Dict(c[1]=>i for (i,c) in enumerate(new_coefficients))
    del = Int[]
    for i in 1:length(terms)
        if _hasvar(terms[i], variable)
            row = terms[i].output_index
            j = Base.get(rowmap, row, 0)
            if !iszero(j) # If it is zero, it means that the row should not be changed
                if iszero(new_coefficients[j][2])
                    push!(del, i)
                else
                    terms[i] = VAT(row, SAT(new_coefficients[j][2], variable))
                end
                rowmap[row] = 0 # We only change the first term of a row
            end
        end
    end
    deleteat!(terms, del)
    for (row, j) in rowmap
        if !iszero(j)
            push!(terms, VAT(row, SAT(new_coefficients[j][2], variable)))
        end
    end
    terms
end
function modifyfunction(f::VAF, change::MulC)
    dim = MOI.output_dimension(f)
    coefficients = change.new_coefficients
    lin = _modifycoefficients(dim, f.terms, change.variable, coefficients)
    VAF(lin, f.constants)
end
function modifyfunction(f::VQF, change::MulC)
    dim = MOI.output_dimension(f)
    coefficients = change.new_coefficients
    lin = _modifycoefficients(dim, f.affine_terms, change.variable, coefficients)
    return VQF(lin, f.quadratic_terms, f.constants)
end
