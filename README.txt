**Setup**

To run the Simulink model, first download the CAD files and make sure they are accessible in your working directory.

Make sure all required project files are in the correct folder before starting. This includes the Simulink file, the user interface file, and any generated motor data files. Do not change any file names.

Connect the arm hardware to the computer and verify that the correct COM port is available before launching the user interface.

**Converting Motion Data**

Use the Simulink file to convert the motion-capture sleeve data into motor command data.

This step takes the recorded motion data and generates the motor output file needed to drive the arm.

Before running the conversion, confirm that the input data file is correct and that the Simulink model is linked to the required files.

**Uploading Data to the Arm**

After the motor data has been generated, open the user interface.

Use the streamer file through the user interface to upload the motor data to the arm.

Once the file has been uploaded, select the motion data you want to run and start the sequence from the interface.

**Running the Arm**

After selecting the desired motor data file, run the motion through the user interface.

Monitor the arm during operation to make sure the movement is correct and that the connection remains stable throughout the run.

If needed, stop the motion from the interface and reload a different motor data file.

**Notes**

Make sure the correct COM port is selected before attempting to upload or run data.

If the Simulink model does not run, check that the CAD files have been downloaded and is in the expected location.

If the arm does not respond, verify the hardware connection, the uploaded motor data, and the selected serial port.

The power and gnd pins ont he green circuit board should be connected to a power supply at 12V, ensure the current is limited to no more than 500 mA.
