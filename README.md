#  Edit Ubuntu Core Gadget Snap Packages

An editor for binary Gadget Snap packages to easily:

  - change volume sizes of the seed and data partitions
  - add/remove entries for auto connections of snaps in the image
  - apply default configurations for snap packages seeded in the image
  - manage kernel command-line parameters
  - change the image file name in the volume definition
  - and indeed change the name of the snap itself

You can search and download existing gadget snaps from the global store with
the built in search function or import a local gadget snap file to edit it.

The gadget snap will only be re-packed after the edit and does not need to be
compiled from source (which provides full cross architecture support).

Note that the existing snap assertions will not match anymore after the edit
and you will have to either re-upload to the store to obtain a fresh signature
or use it with a "dangerous" model assertion for local image builds.

If you need to load/save gadget files to/from external media, you need to
connect the removable-media snap interface with:

    sudo snap connect gadget-editor:removable-media

## Building

Just clone this tree and run `snapcraft pack` in the top-level of it.


## Screenshots 

 <img width="2664" height="1638" alt="Pasted image" src="https://github.com/user-attachments/assets/ea3e9bf7-5897-4fb3-bfd3-be940647db70" />
 <img width="2664" height="1638" alt="Pasted image (2)" src="https://github.com/user-attachments/assets/e76a46ec-4585-46ad-b6a1-62e39640d9d7" />
 <img width="2664" height="1638" alt="Pasted image (3)" src="https://github.com/user-attachments/assets/e0b98778-3c8c-4e2e-b5d7-312dd4d58d4e" />
 <img width="2664" height="1638" alt="Pasted image (4)" src="https://github.com/user-attachments/assets/5894a14d-6072-4d12-9aa8-fdf76f7a5f1d" />
 <img width="2664" height="1638" alt="Pasted image (5)" src="https://github.com/user-attachments/assets/38a28f78-6f0d-4175-828a-761a784cd7bb" />
