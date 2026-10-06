# source this: the labelled beyond-human body for every L6 command + the coordinator's thread caps (machine oversubscribed; results are deterministic)
export ROBOLAB_CALIB=v4 ROBOLAB_PROFILE=beyond ROBOLAB_PROFILE_PARTS=strength,speed,tendon,activation
export OMP_NUM_THREADS=1 VECLIB_MAXIMUM_THREADS=1 OPENBLAS_NUM_THREADS=1 MKL_NUM_THREADS=1
# usage: $LJ6NICE .venv/bin/python ...
export LJ6NICE="nice -n 10"
