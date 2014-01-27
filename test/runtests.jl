using SPICE
using Base.Test

this_path = dirname(Base.source_path())
data_path = joinpath(this_path,"data")
!isdir(data_path) && mkdir(data_path)
ngspice(file) = run(joinpath(this_path,file)|>((ignorestatus(setenv(`ngspice`;dir=data_path))|>DevNull).>DevNull))
ngspice("files/01.cir")
data1 = read_ascii_table(joinpath(data_path,"01-a.data"),["vo1","vo2","Iin"])
@test size(data1)[1] == 501