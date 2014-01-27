using BinDeps

@BinDeps.setup

ngspice = library_dependency("ngspice", aliases=["libngspice"])

provides(Sources,URI("http://downloads.sourceforge.net/project/ngspice/ng-spice-rework/26/ngspice-26.tar.gz?r=http%3A%2F%2Fsourceforge.net%2Fprojects%2Fngspice%2Ffiles%2Fng-spice-rework%2F26%2F&ts=1390792255&use_mirror=hivelocity"),ngspice)

provides(BuildProcess,Autotools(libtarget="src/.libs/libngspice.$(Base.Sys.shlib_ext)",configure_options=["--with-ngshared"]),ngspice)

@BinDeps.install [:ngspice => :ngspice]