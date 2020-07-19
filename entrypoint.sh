#!/bin/bash

cleanup() {
  umount "${MOUNT_TARGET}"
}

#Trap all different quit signals
trap 'cleanup' SIGTERM SIGINT SIGQUIT SIGABRT SIGKILL SIGUSR1 SIGUSR2

# Wait for the tunnel adapter to actually be ready
counter=5
while true; do
  if [[ "$counter" -lt 0 ]]; then
    break
  fi

  if [[ $( ifconfig -s | grep tun ) ]]; then
    echo "found tun adapter"
    ifconfig
    break
  else
    echo "tun adapter not ready yet"
    counter=$((counter-1))
    sleep 10s
  fi
done


if [[ $( ifconfig -s | grep tun ) ]]; then
  echo "running mount command"
  # Turn on to debug mount issues
  # echo "${MOUNT_COMMAND}"
  eval "${MOUNT_COMMAND}"
  tail -f /dev/null &
  wait $!
else
  exit 1
fi

cleanup
