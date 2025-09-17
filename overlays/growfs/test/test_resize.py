from pathlib import Path

def test_rootfs_resized(host):
    """
    Test that rootfs was resized correctly.
    """
    root_partition_path = "/dev/disk/by-partlabel/system_a"

    root_partition_link = host.file(root_partition_path)
    assert root_partition_link.exists
    assert root_partition_link.is_symlink

    root_part_dev = Path(root_partition_link.linked_to)
    root_device_name = host.run("lsblk -n -o pkname %s" % root_part_dev).stdout.strip()
    root_device_path = "/dev/%s" % root_device_name
    
    root_device = host.block_device(root_device_path)
    assert root_device.is_partition is False

    root_partition = host.block_device(root_partition_path)
    assert root_partition.is_partition is True

    # Check underlying partition was grown to fill the disk
    assert root_partition.size > 0.8 * root_device.size

    df_output = host.run("df / --output=avail,used,size -B1")
    # Get the available and used space from the output
    available, used, size = map(int, df_output.stdout.splitlines()[1].split())

    assert size > 0.98 * root_partition.size
    # Check that we are using less than 50% of the total space
    assert available > used

