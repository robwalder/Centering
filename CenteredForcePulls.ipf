#pragma rtGlobals=1		// Use modern global access method.
#pragma version=9.1

// For version 9.1
// Changed file name to Centered Force Pulls.  Going to keep this for the rest of the upgrades.  

#include "ForceRamp",version>=2
#include "ConstantForceMotion"
#include "SearchForMolecules", version>=2
#include "CFPReport"
#include "ForceClamp_rw", version>=3
#include "ZeroThePD"
#include "InvolsCheck"
#include "WaveDimNote"


Menu "Centered Force Pulls"
	"Initialize CFP", InitializeCFP()
	"Start CFP", StartCFP()
	"Stop CFP",StopCFP()
	"Show Main CFP Panel",DisplayCFPPanel("CFP_Panel")
	"Show First Ramp Panel",DisplayCFPPanel("FirstRampCFP")
	"Show Centered Ramp Panel",DisplayCFPPanel("CenteredRampCFP")
End


// Initialize the centered force pull program
Function InitializeCFP([ShowUserInterface])
	
	Variable ShowUserInterface
	If(ParamIsDefault(ShowUserInterface))
		ShowUserInterface=1
	EndIf

	// In case we want to do a centered force clamp
	InitializeForceClamp()

	//Build Datafolder for CFP and set that as current datafolder
	NewDataFolder/O root:CFP
	SetDataFolder root:CFP
		
	// Load External Parm waves
	String PathIn=FunctionPath("")
	NewPath/Q/O CenteringParms ParseFilePath(1, PathIn, ":", 1, 0) +"Parms"
	LoadWave/H/Q/O/P=CenteringParms "CenteredRamp_QuickSettings.ibw"	
	LoadWave/H/Q/O/P=CenteringParms "CenteredRamp_Settings.ibw"	
	LoadWave/H/Q/O/P=CenteringParms "CenteredRamp_WaveNames.ibw"	
	LoadWave/H/Q/O/P=CenteringParms "CenteredRamp_WaveNamesQS.ibw"	
	LoadWave/H/Q/O/P=CenteringParms "CenteringQuickSettings.ibw"	
	LoadWave/H/Q/O/P=CenteringParms "CenteringSettings.ibw"	
	LoadWave/H/Q/O/P=CenteringParms "CFPQuickSettings.ibw"	
	LoadWave/H/Q/O/P=CenteringParms "CFPSettings.ibw"	
	LoadWave/H/Q/O/P=CenteringParms "FirstRamp_QuickSettings.ibw"	
	LoadWave/H/Q/O/P=CenteringParms "FirstRamp_Settings.ibw"	
	LoadWave/H/Q/O/P=CenteringParms "FirstRamp_WaveNames.ibw"	
	LoadWave/H/Q/O/P=CenteringParms "FirstRamp_WaveNamesQS.ibw"	
	LoadWave/H/Q/O/P=CenteringParms "PresetPullingVelocities.ibw"	

	// Make waves for circle 
	MakeCFCSettingsWave(OutputWaveName="Circle_Settings")
	MakeCFCWaveNamesCallback(OutputWaveName="Circle_WaveNames")
	Wave/T Circle_WaveNames
	Circle_WaveNames[%XSensor]="XSensorCircle"
	Circle_WaveNames[%YSensor]="YSensorCircle"
	Circle_WaveNames[%ZSensor]="ZSensorCircle"
	Circle_WaveNames[%DefV]="DefVCircle"
	Circle_WaveNames[%Callback]="CircleCallback()"

	// Make waves for moving to a point
	MakeMoveToPointCFSettingsWave(OutputWaveName="MoveToPoint_Settings")
	
	// make waves for sampling deflection and zsensor at discrete points.
	MakeSampleZWavesCallback(OutputWaveName="SampleAtPoint_WaveNames")
	MakeSampleZSettingsWave(OutputWaveName="SampleAtPoint_Settings")
	Wave/T SampleAtPoint_WaveNames
	SampleAtPoint_WaveNames[%XSensor]="XSensorPoint"
	SampleAtPoint_WaveNames[%YSensor]="YSensorPoint"
	SampleAtPoint_WaveNames[%ZSensor]="ZSensorPoint"
	SampleAtPoint_WaveNames[%DefV]="DefVPoint"
	SampleAtPoint_WaveNames[%Callback]="SampleZCallback()"

	// Make waves for fine centering cross
	MakeCFCrossSettingsWave(OutputWaveName="FineCentering_Settings")
	MakeCFCrossWaveNamesCallback(OutputWaveName="FineCentering_WaveNames")
	Wave/T FineCentering_WaveNames
	FineCentering_WaveNames[%XSensor]="XSensorFine"
	FineCentering_WaveNames[%YSensor]="YSensorFine"
	FineCentering_WaveNames[%ZSensor]="ZSensorFine"
	FineCentering_WaveNames[%DefV]="DefVFine"
	FineCentering_WaveNames[%Callback]="FineCenteringCallback()"


	Make/N=256/O DeflectionOffsetData

	DisplayCFPPanel("CFP_Panel")	
	
	ResetCurrentDataWaves()
	InitSearch()
	InitZeroThePD()
	InitCheckInvols()
	DisplayCFPPanel("FirstRampCFP")
	DisplayCFPPanel("CenteredRampCFP")
	
End // InitializeCTFC

//  This function controls the sequence of events for the centering protocol
//  It also checks to make sure the molecule didn't detach.  If it detached, then start a new iteration.  
Function CFP_MainLoop()
	
	Wave CFPSettings = root:CFP:CFPSettings
	Wave/T Centering = root:CFP:CenteringSettings
	Wave Circles_X = root:CFP:Circles_X	
	Wave Circles_Y = root:CFP:Circles_Y
	Wave Circles_Z = root:CFP:Circles_Z
	Wave XTargets = root:CFP:XTargets
	Wave YTargets = root:CFP:YTargets
	Wave ZTargets = root:CFP:ZTargets
	Wave DeflTargets = root:CFP:DefTargets
	Wave XSensorCirc = root:CFP:XSensorCircle
	Wave YSensorCirc = root:CFP:YSensorCircle
	Wave ZSensorCirc = root:CFP:ZSensorCircle
	Wave Defl_VoltsCirc = root:CFP:DefVCircle

	Variable XCurrentPosition_Volts = td_rv("Cypher.LVDT.X")
	Variable YCurrentPosition_Volts = td_rv("Cypher.LVDT.Y")
	Variable ZCurrentPosition_Volts= td_rv("Cypher.LVDT.Z")
	
	// Check to see if zsensor has railed.  Probably means the molecule has disconnected.	
	If ((ZCurrentPosition_Volts < -1.06922)&&!(StringMatch(Centering[%State],"FirstRamp")))
		Centering[%State] = "Railed"
	EndIf
	
	If (str2num(Centering[%$"EndProgram"])== 1)
		Centering[%State] = "EndProgram"
	EndIf
		
	Strswitch (Centering[%State])
		case "FirstRamp":
			Wave FirstRamp_Settings=root:CFP:FirstRamp_Settings
			Wave/T FirstRamp_WaveNames=root:CFP:FirstRamp_WaveNames
			FirstRamp_Settings[%DefVOffset]=CFPSettings[%DeflectionOffset]
			DoForceRampFiltered(FirstRamp_Settings,FirstRamp_WaveNames,CFPSettings[%TriggerFilterFreq])
			
		break
		case "Circle":
			Wave Circle_Settings=root:CFP:Circle_Settings
			Wave/T Circle_WaveNames=root:CFP:Circle_WaveNames
			Circle_Settings[%Force_N]=CFPSettings[%TargetForce]
			Circle_Settings[%DefVOffset]=CFPSettings[%DeflectionOffset]
			Circle_Settings[%Radius_m]=CFPSettings[%CircleRadius]
			Circle_Settings[%CenterX_V]=XCurrentPosition_Volts
			Circle_Settings[%CenterY_V]=YCurrentPosition_Volts
			
			Circles_X[0]= XCurrentPosition_Volts
			Circles_Y[0]= YCurrentPosition_Volts
			Circles_Z[0]= ZCurrentPosition_Volts

			CFCircle(Circle_Settings,Circle_WaveNames)
		break
		case "DiscreteMoves":
			Wave MoveToPoint_Settings=root:CFP:MoveToPoint_Settings
			
			Variable Iteration = CFPSettings[%StepIteration]
			MoveToPoint_Settings[%XPosition_V]=XTargets[Iteration]
			MoveToPoint_Settings[%YPosition_V]=YTargets[Iteration]
			MoveToPoint_Settings[%Force_N]=CFPSettings[%TargetForce]
			MoveToPoint_Settings[%DefVOffset]=CFPSettings[%DeflectionOffset]

			// If more than one discrete point recorded, then test them to see if we have passed the point of maximum extension
			// If not, then move to the next point
			If (Iteration == 1)
				MoveToPointCF(MoveToPoint_Settings,Callback="StepsCallback()")			
			ElseIf ((Iteration>=2)&&(Iteration<=13))
				Variable Increasing1=ZTargets[Iteration-1]>ZTargets[Iteration-2]
				Variable Increasing2=ZTargets[Iteration-2]>ZTargets[Iteration-3]
				Variable MovingAwayFromCenter = Increasing1&&Increasing2
				
				If(MovingAwayFromCenter)
					Centering[%State] = "FineTuneCenter"
	
					MoveToPoint_Settings[%XPosition_V]=XTargets[Iteration-3]
					MoveToPoint_Settings[%YPosition_V]=YTargets[Iteration-3]
					
					Wave FineCentering_Settings=root:CFP:FineCentering_Settings
					FineCentering_Settings[%CenterX_V]=XTargets[Iteration-3]
					FineCentering_Settings[%CenterY_V]=YTargets[Iteration-3]
						
					MoveToPointCF(MoveToPoint_Settings,Callback="CFP_MainLoop()")
				Else
					MoveToPointCF(MoveToPoint_Settings,Callback="StepsCallback()")
				EndIf
			
			EndIf // iteration >1
			If (Iteration>13)
				StopZFeedbackLoop()			
				FinishCFP()
			Endif						
		break
		case "FineTuneCenter":
			Wave FineCentering_Settings=root:CFP:FineCentering_Settings
			Wave/T FineCentering_WaveNames=root:CFP:FineCentering_WaveNames
			FineCentering_Settings[%Force_N]=CFPSettings[%TargetForce]
			FineCentering_Settings[%DefVOffset]=CFPSettings[%DeflectionOffset]
			// This is a fix in version 7.1
			// Reads the distance to move from center for the distance to move in the fine centering.  Was stuck at 100nm in versions 6 and 7.
			FineCentering_Settings[%DistanceFromCenter_m]=CFPSettings[%'Distance to move from center']

			If(CFPSettings[%FineCenteringIteration]<=CFPSettings[%$"Max Iterations"])
				CFCross(FineCentering_Settings,FineCentering_WaveNames)
			Else
				StopZFeedbackLoop()	
				SaveCurrentData() 		
				FinishCFP()
			EndIf
		break
		case "Railed":
			StopZFeedbackLoop()		
			SaveCurrentData()  // This is just in here temporarily for testing purposes.  Trying to see if there is a bug to fix.	
			FinishCFP()
		break
		case "EndProgram":
			print "Centering Program Ended"
			StopZFeedbackLoop()			

		break
		default:	
			print "Error, in default state.  Check your program for problems."
	EndSwitch
	
End

Function ResetCurrentDataWaves()
	SetDataFolder root:CFP
	
	// Make Waves for Force Triggering
	Make/N=(1024)/O ZSensor_Ramp1,DefV_Ramp1,ZSensor_Ramp2,DefV_Ramp2

	// Make waves for centering
	Make/O/N=2 Circles_X,Circles_Y,Circles_Z
	Make/O/N=13 XTargets,YTargets,ZTargets,DefTargets
	Make/O/N=10 FineCenterX,FineCenterY,FineCenterZ
	Make/N=(1024)/O XSensorCircle,YSensorCircle,ZSensorCircle
	FineCenterX=0
	FineCenterY=0
	FineCenterZ=0
	// Fine Centering motion and fit waves
	Make/O/N=(1024) XSensorFine,YSensorFine,ZSensorFine,DefVFine,XFit, YFit,XPos,YPos,ZSensor_X,ZSensor_Y
	
	// Kill Saved Fits to fine centering
	String XFitWaveNames= WaveList("XFit_*", ";" ,"" )
	String YFitWaveNames= WaveList("YFit_*", ";" ,"" )
	String XPosWaveNames= WaveList("XPos_*", ";" ,"" )
	String YPosWaveNames= WaveList("YPos_*", ";" ,"" )
	String ZSensorXWaveNames= WaveList("ZSensorX_*", ";" ,"" )
	String ZSensorYWaveNames= WaveList("ZSensorY_*", ";" ,"" )
	
	Variable NumFitWavestoKill=ItemsInList(XFitWaveNames, ";")
	Variable Counter=0
	For(Counter=0;Counter<NumFitWavesToKill;Counter+=1)
		String XFitWaveName=StringFromList(Counter, XFitWaveNames)
		String YFitWaveName=StringFromList(Counter, YFitWaveNames)
		String XPosWaveName=StringFromList(Counter, XPosWaveNames)
		String YPosWaveName=StringFromList(Counter, YPosWaveNames)
		String ZSensorXWaveName=StringFromList(Counter, ZSensorXWaveNames)
		String ZSensorYWaveName=StringFromList(Counter, ZSensorYWaveNames)
		KillWaves $XFitWaveName,$YFitWaveName,$XPosWaveName,$YPosWaveName,$ZSensorXWaveName,$ZSensorYWaveName
	EndFor
	
	// Reset selected centering settings
	Wave CFPSettings=root:CFP:CFPSettings
	CFPSettings[%$"Center Found?"]=0
	CFPSettings[%$"FineCenteringIteration"]=0
	CFPSettings[%$"StepIteration"]=0
	CFPSettings[%$"Center X"]=0
	CFPSettings[%$"Center Y"]=0
	CFPSettings[%$"FoundMolecule"]=0
	
End // ResetCurrentDataWaves

Function DisplayCFPPanel(PanelName)
	String PanelName	

	DoWindow/F $PanelName
	If (V_flag==0)		
		Wave FirstRamp_Settings=root:CFP:FirstRamp_Settings
		Wave/T FirstRamp_WaveNames=root:CFP:FirstRamp_WaveNames
		Wave CenteredRamp_Settings=root:CFP:CenteredRamp_Settings
		Wave/T CenteredRamp_WaveNames=root:CFP:CenteredRamp_WaveNames

		StrSwitch(PanelName)
			Case "CFP_Panel":
				Execute/Q "CFP_Panel()"
				MoveWindow/W=CFP_Panel 722,10,895,350
			break
			Case "FirstRampCFP":
				MakeForceRampPanel(FirstRamp_Settings,FirstRamp_WaveNames,PanelName="FirstRampCFP",WindowName="CFP First Ramp")
				MoveWindow/W=FirstRampCFP 400,10,550,285
			break
			Case "CenteredRampCFP":
				MakeForceRampPanel(CenteredRamp_Settings,CenteredRamp_WaveNames,PanelName="CenteredRampCFP",WindowName="CFP Centered Ramp")
				MoveWindow/W=CenteredRampCFP 560,10,710,285
			break
			
		EndSwitch
		
	EndIf

End

Function DisplayCFPInfo(TargetDisplay,[TargetDataFolder])
	String TargetDisplay,TargetDataFolder
	String NamePrefix
	
	If(ParamIsDefault(TargetDataFolder))
		TargetDataFolder="root:CFP"
	EndIf
	
	If(StringMatch(TargetDataFolder,"root:CFP"))
		NamePrefix="Current"
	Else
		NamePrefix=StringFromList(2,TargetDataFolder,":")
	EndIf
	
	SetDataFolder $TargetDataFolder
	String DisplayName=NamePrefix+TargetDisplay
	DoWindow/F $DisplayName
	
	If (V_flag==0)		
		strswitch(TargetDisplay)
			case "FirstRampTable":
				Edit/K=1/W=(7.5,92.75,508.5,288.5)/N=$DisplayName  FirstRamp_Settings.ld
			break
			case "CenteringTable": 
				Edit/K=1/W=(5.25,323,336,535.25)/N=$DisplayName CenteringSettings.ld
			break	
			case "CFPSettings": 
				Edit/K=1/W=(5.25,323,336,535.25)/N=$DisplayName CFPSettings.ld
			break	
			case "CircleSettings":
				Edit/K=1/W=(3.75,564.5,338.25,810.5)/N=$DisplayName Circle_Settings.ld
			break	
			case "FineCenteringSettings":
				Edit/K=1/W=(3.75,564.5,338.25,810.5)/N=$DisplayName FineCentering_Settings.ld
			break	
			case "SampleAtPointSettings":
				Edit/K=1/W=(3.75,564.5,338.25,810.5)/N=$DisplayName SampleAtPoint_Settings.ld
			break	
			case "MoveToPointSettings":
				Edit/K=1/W=(3.75,564.5,338.25,810.5)/N=$DisplayName MoveToPoint_Settings.ld
			break	
			case "CenteredRampSettings":
				Edit/K=1/W=(3.75,564.5,338.25,810.5)/N=$DisplayName CenteredRamp_Settings.ld
			break	
			case "CurrentCenteringGraphs":
				DisplayReport("Current")
			break	
			case "PresetPullingVelocities":
				Edit/K=1/W=(3.75,564.5,338.25,810.5)/N=$DisplayName PresetPullingVelocities.ld
			break	
			
		endswitch  // TargetDisplay
	EndIf		
	SetDataFolder root:CFP

End // DisplayInfo


Function StartCFP()
	Wave/T CenteringSettings = root:CFP:CenteringSettings
	CenteringSettings[%State]="FirstRamp"
	CenteringSettings[%$"EndProgram"]="0"
	
	Variable DeflectionOffset=td_rv("Deflection")
	Wave CFPSettings=root:CFP:CFPSettings
	CFPSettings[%DeflectionOffset]=DeflectionOffset
	CFPSettings[%$"Center Found?"]=0
	DetermineOffset()
End //StartCFP()

Function StopCFP()
	Wave/T CenteringSettings=root:CFP:CenteringSettings
	CenteringSettings[%$"EndProgram"]="1"
End

Function DetermineOffset()
	Wave DeflectionOffsetData=root:CFP:DeflectionOffsetData
	Variable Error=0
	Error+= td_xSetInWave(0, "0,0", "Deflection", DeflectionOffsetData, "DetermineOffsetCallback()",100)

	// Execute motion
	Error +=td_WriteString("Event.0", "once")

	if (Error>0)
		print "Error in DetermineOffset: ", Error
	endif
End

Function DetermineOffsetCallback()
	Wave DeflectionOffsetData=root:CFP:DeflectionOffsetData
	WaveStats/Q DeflectionOffsetData
	Variable DeflectionOffset=V_avg
	
	Wave CFPSettings=root:CFP:CFPSettings
	CFPSettings[%DeflectionOffset]=DeflectionOffset
	ResetCurrentDataWaves()
	CFP_MainLoop()
End

// This callback exectues when the CTFC is done
Function FirstRampCallback() 
	
	//print "FirstRampCallback()"
	Wave/T TriggerInfo=root:CFP:TriggerInfo_Ramp1
	Wave/T CenteringSettings=root:CFP:CenteringSettings
	Wave CFPSettings=root:CFP:CFPSettings
	Wave DefVolts=root:CFP:DefV_Ramp1
	Wave ZSensorVolts = root:CFP:ZSensor_Ramp1
	variable Error = 0
	variable MoleculeAttached =1 // Default assumption is molecule will attach
	
	// Set current state to First Ramp callback
	CenteringSettings[%State]="FirstRampCallback"
	
	// Save initial force ramp with suffix _IFR (stands for initial force ramp)
	String SaveName=CenteringSettings[%SaveName]+"_IFR"
	SaveAsAsylumForceRamp(SaveName,CFPSettings[%MasterIteration],DefVolts,ZSensorVolts)
	
	// Check to see if molecule is attached.  If Triggertime2 is greater than 400,000, then molecule did NOT attach
	Error+=td_ReadGroup("ARC.CTFC",TriggerInfo)
	if (str2num(TriggerInfo[%TriggerTime2])> 400000)
		MoleculeAttached=0
	endif
	
	If (Error>0)
		Print "Error in FirstRampCallback"
	EndIf

	// Execute Centering Routine if molecule is attached
	if (MoleculeAttached==1)  
		CFPSettings[%FoundMolecule]=1

		StrSwitch(CenteringSettings[%CenteringMode])
			case "FullCentering":
				CenteringSettings[%State]="Circle"
				CFP_MainLoop()
			break
			case "JustFineCentering":
				CenteringSettings[%State]="FineTuneCenter"
				Wave FineCentering_Settings=root:CFP:FineCentering_Settings
				FineCentering_Settings[%CenterX_V]=td_rv("Cypher.LVDT.X")
				FineCentering_Settings[%CenterY_V]=td_rv("Cypher.LVDT.Y")

				CFP_MainLoop()

			break
		EndSwitch
	endif
	
	// If no molecule attached, then finish this
	If (MoleculeAttached==0)
		FinishCFP()
	endif

End //FirstRampCallback

Function CircleCallback() 
	
	Wave/T CenteringSettings=root:CFP:CenteringSettings
	Wave CFPSettings=root:CFP:CFPSettings
	Wave XSensorCircle=root:CFP:XSensorCircle
	Wave YSensorCircle = root:CFP:YSensorCircle
	Wave ZSensorCircle = root:CFP:ZSensorCircle
	Wave Circles_X=root:CFP:Circles_X
	Wave Circles_Y=root:CFP:Circles_Y
	Wave Circles_Z=root:CFP:Circles_Z
	Wave XTargets = root:CFP:XTargets
	Wave YTargets = root:CFP:YTargets
	Wave ZTargets = root:CFP:ZTargets

	
	CenteringSettings[%State] = "CircleCallback"
	
	WaveStats/Q ZSensorCircle
 	Variable MinDirectionRowLoc = V_minRowLoc

	Circles_X[1]= XSensorCircle[MinDirectionRowLoc]
	Circles_Y[1]= YSensorCircle[MinDirectionRowLoc]
	Circles_Z[1]= ZSensorCircle[MinDirectionRowLoc]
	
	Variable YIncrement = Circles_Y[1]-Circles_Y[0]
	Variable XIncrement = Circles_X[1]-Circles_X[0]
	
	XTargets = XIncrement*(p-1)+Circles_X[0]
	YTargets = YIncrement*(p-1)+Circles_Y[0]
	ZTargets=0
	
	CFPSettings[%StepIteration] = 1
	CenteringSettings[%State] = "DiscreteMoves"
	CFP_MainLoop()
	
End // CircleCallback

Function StepsCallback() 
	
	Wave/T CenteringSettings=root:CFP:CenteringSettings
	Wave CFPSettings=root:CFP:CFPSettings
	Wave XTargets = root:CFP:XTargets
	Wave YTargets = root:CFP:YTargets
	Wave ZTargets = root:CFP:ZTargets
	Wave SampleAtPoint_Settings = root:CFP:SampleAtPoint_Settings
	Wave/T SampleAtPoint_WaveNames = root:CFP:SampleAtPoint_WaveNames

	Variable CurrentIteration=CFPSettings[%StepIteration]

	CenteringSettings[%State] = "SampleZSensor"
	SampleAtPoint_Settings[%Force_N]=CFPSettings[%Targetforce]
	SampleAtPoint_Settings[%DefVOffset]=CFPSettings[%DeflectionOffset]
	
	// Sample X,Y,Z, and Deflection at this point, while maintaining constant force
	SampleZSensorCF(SampleAtPoint_Settings,SampleAtPoint_WaveNames)
	
End // StepsCallback

Function SampleZCallback()
	Wave/T CenteringSettings=root:CFP:CenteringSettings
	Wave CFPSettings=root:CFP:CFPSettings
	Wave XTargets = root:CFP:XTargets
	Wave YTargets = root:CFP:YTargets
	Wave ZTargets = root:CFP:ZTargets
	Wave SampleAtPoint_Settings = root:CFP:SampleAtPoint_Settings
	Wave/T SampleAtPoint_WaveNames = root:CFP:SampleAtPoint_WaveNames
	Wave ZSensor=root:CFP:ZSensorPoint
	Variable CurrentIteration=CFPSettings[%StepIteration]
	
	CenteringSettings[%State] = "SampleZCallback"
	// Average Z Sensor wave for current z sensor position
	WaveStats/Q ZSensor
	ZTargets[CurrentIteration]=V_avg
	
	// Move to next iteration and go back to main program loop
	CFPSettings[%StepIteration] = CurrentIteration+1
	CenteringSettings[%State] = "DiscreteMoves"
	CFP_MainLoop()

End

Function FineCenteringCallback()

	Wave/T CenteringSettings=root:CFP:CenteringSettings
	Wave CFPSettings=root:CFP:CFPSettings
	Variable FineCenterIteration = CFPSettings[%FineCenteringIteration]
	Wave FineCenterX=root:CFP:FineCenterX
	Wave FineCenterY=root:CFP:FineCenterY
	Wave FineCenterZ=root:CFP:FineCenterZ
	Wave XSensorFine=root:CFP:XSensorFine
	Wave YSensorFine=root:CFP:YSensorFine
	Wave ZSensorFine=root:CFP:ZSensorFine
	Wave DefVFine=root:CFP:DefVFine
	Variable MaxIterations = CFPSettings[%$"Max Iterations"]
	Variable CriticalFitDifference = CFPSettings[%$"Critical Fit Difference"]
		
	// Split the raw waves into data for centering calculation
	Variable NumPoints=numpnts(XSensorFine)
	Variable Increment=Floor(NumPoints/16)

	Duplicate/O/R=[3*Increment+1,5*Increment] XSensorFine, XPos
	Duplicate/O/R=[3*Increment+1,5*Increment] ZSensorFine, ZSensor_X 
	Duplicate/O/R=[11*Increment+1,13*Increment] YSensorFine, YPos
	Duplicate/O/R=[11*Increment+1,13*Increment] ZSensorFine, ZSensor_Y	
	
	// Save this iteration data
	String CurrentIterationStr=num2str(FineCenterIteration)
	String XPosName =  "root:CFP:XPos_"+ CurrentIterationStr
	String YPosName =  "root:CFP:YPos_"+ CurrentIterationStr
	String ZSensor_XName =  "root:CFP:ZSensorX_"+ CurrentIterationStr
	String ZSensor_YName =  "root:CFP:ZSensorY_"+ CurrentIterationStr
		
	Duplicate/O XPos, $XPosName
	Duplicate/O YPos, $YPosName
	Duplicate/O ZSensor_X, $ZSensor_XName
	Duplicate/O ZSensor_Y, $ZSensor_YName	
		
	// Calculate Center Positions
	Variable CenterX = CalculateCenterPosition(XPos,ZSensor_X)
	Duplicate/O Quadratic_Fit, XFit
	String XFitName =  "root:CFP:XFit_"+ CurrentIterationStr
	Duplicate/O Quadratic_Fit, $XFitName
	
	Variable CenterY = CalculateCenterPosition(YPos,ZSensor_Y)
	Duplicate/O Quadratic_Fit, YFit
	String YFitName =  "root:CFP:YFit_"+ CurrentIterationStr
	Duplicate/O Quadratic_Fit, $YFitName
	
	FineCenterX[FineCenterIteration]=CenterX
	FineCenterY[FineCenterIteration]=CenterY
	
	Wave MoveToPoint_Settings=root:CFP:MoveToPoint_Settings
	
	MoveToPoint_Settings[%XPosition_V]=CenterX
	MoveToPoint_Settings[%YPosition_V]=CenterY
	MoveToPoint_Settings[%Force_N]=CFPSettings[%TargetForce]
	MoveToPoint_Settings[%DefVOffset]=CFPSettings[%DeflectionOffset]
	
	MoveToPointCF(MoveToPoint_Settings,Callback="MoveToNewCenterCallback()")			

End // Centering Callback

Function MoveToNewCenterCallback()

	Wave/T CenteringSettings=root:CFP:CenteringSettings
	Wave CFPSettings=root:CFP:CFPSettings
	Variable FineCenterIteration = CFPSettings[%FineCenteringIteration]
	Wave FineCenterX=root:CFP:FineCenterX
	Wave FineCenterY=root:CFP:FineCenterY
	Wave FineCenterZ=root:CFP:FineCenterZ
	Wave XSensorFine=root:CFP:XSensorFine
	Wave YSensorFine=root:CFP:YSensorFine
	Wave ZSensorFine=root:CFP:ZSensorFine
	Wave DefVFine=root:CFP:DefVFine
	Wave FineCentering_Settings=root:CFP:FineCentering_Settings
	Variable MaxIterations = CFPSettings[%$"Max Iterations"]
	Variable CriticalFitDifference = CFPSettings[%$"Critical Fit Difference"]
	
	Variable XCriticalFitDifference = Abs(CriticalFitDifference/GV("XLVDTSens")) // X Critical difference in LVDT volts
	Variable YCriticalFitDifference = Abs(CriticalFitDifference/GV("YLVDTSens")) // Y Critical difference in LVDT volts
	
	// Determine if we found the center.  End if center is found, or if we reach the max number of iterations.
	Variable FoundCenter=0
	If (FineCenterIteration==1)  // If this is the first iteration, run a second iteration to be sure we found the center
		FoundCenter=0
	ElseIf ((FineCenterIteration<MaxIterations)&&(FineCenterIteration>1)) // If we are in between 2 iterations and the max iterations, see if we found a good center
		variable XDiff = Abs((FineCenterX[FineCenterIteration-1]-FineCenterX[FineCenterIteration]))
		variable YDiff =  Abs((FineCenterY[FineCenterIteration-1]-FineCenterY[FineCenterIteration]))
		
		If ((XDiff<XCriticalFitDifference)&&(YDiff<YCriticalFitDifference) ) 
			FoundCenter=1
			CFPSettings[%$"Center Found?"] = 1
			CFPSettings[%$"Center X"] = FineCenterX[FineCenterIteration] 
			CFPSettings[%$"Center Y"] = FineCenterY[FineCenterIteration]
			
		Else	// If not, try another centering
			FoundCenter=0
		Endif
		
	Else   // If we have reached the maximum number of iterations, go to center and ramp
		FoundCenter=0
	EndIf
	
 	// Now, if center found then execute a ramp to get centered force data
	If (FoundCenter)
		Wave CenteredRamp_Settings=root:CFP:CenteredRamp_Settings
		Wave/T CenteredRamp_WaveNames=root:CFP:CenteredRamp_WaveNames
		CFPSettings[%NumCenteredForcePulls]+=1
		// If using preset values for pulling velocities, set those now.
		If(CFPSettings[%UsePresetPullingVelocities])
			Wave PPV=root:CFP:PresetPullingVelocities
			Duplicate/O/R=[0,*][2] PPV,PPVCounts
			Redimension/N=-1 PPVCounts
			Variable PPVIndex=0
			PPVIndex= GetIndex(PPVCounts,CFPSettings[%NumCenteredForcePulls])		
			CenteredRamp_Settings[%'Retract Velocity']=PPV[PPVIndex][%PullingVelocity]
			KillWaves PPVCounts
			
		EndIf

		Variable UsingForceClamp=WhichListItem(CenteringSettings[%FoundCenterAction],"ForceClamp;RampThenClamp;")!=-1
		// If we are using a force clamp, then set the force clamp callback and the deflection offset
		If(UsingForceClamp)
			Wave/T FCWaveNamesCallback=root:ForceClamp:FCWaveNamesCallback
			Wave FCSettings=root:ForceClamp:FCSettings
			FCWaveNamesCallback[%Callback]="CenteredForcePullCallback()"
			FCSettings[%DefVOffset]=CFPSettings[%DeflectionOffset]
			String CurrentIterationStr
			sprintf CurrentIterationStr, "%04d", CFPSettings[%MasterIteration]
			FCWaveNamesCallback[%NearestForcePull]=CenteringSettings[%SaveName]+"_CFR"+CurrentIterationStr
		EndIf
		
		StopZFeedbackLoop()
		CenteringSettings[%State] = "CenteredForcePull"

		// Now determine which action to take.
		StrSwitch(CenteringSettings[%FoundCenterAction])
		
			case "ForceRamp":
				CenteredRamp_WaveNames[%Callback]="CenteredForcePullCallback()"
				DoForceRamp(CenteredRamp_Settings,CenteredRamp_WaveNames)
			break
			case "RampThenClamp":
				CenteringSettings[%State] = "RampThenClamp"
				// Setup the force ramp callback to activate the force clamp
				CenteredRamp_WaveNames[%Callback]="DoForceClamp()"
				// Do the force ramp
				DoForceRamp(CenteredRamp_Settings,CenteredRamp_WaveNames)
			break
			case "ForceClamp":
				CenteringSettings[%State] = "ForceClamp"
				DoForceClamp()
			break
			case "RampThenPause":
				// Set ramp callback to to pause callback
				CenteredRamp_WaveNames[%Callback]="PauseCFPCallback()"
				DoForceRamp(CenteredRamp_Settings,CenteredRamp_WaveNames)
			break
			case "Pause":
				CenteringSettings[%State] = "StopForUserAction"
				PauseCFPCallback()
			break
			case "ForceRampCustomCallback":
				DoForceRamp(CenteredRamp_Settings,CenteredRamp_WaveNames)
			break
			case "MoveThenForceRamp":
				Wave MoveToOffset_Settings=root:CFP:MoveToPoint_Settings
				ControlInfo/W=CFP_Panel LateralMoveSV
				Variable DistanceToMoveV=V_value/GV("XLVDTSens")
				
				MoveToOffset_Settings[%XPosition_V]=td_rv("Cypher.LVDT.X")+DistanceToMoveV
				MoveToOffset_Settings[%YPosition_V]=td_rv("Cypher.LVDT.Y")
				MoveToOffset_Settings[%Force_N]=CFPSettings[%TargetForce]
				MoveToOffset_Settings[%DefVOffset]=CFPSettings[%DeflectionOffset]
		
				MoveToPointCF(MoveToOffset_Settings,Callback="MoveThenRampCallback()")			
				
			break
			case "RampThenFastClamp":
				CenteringSettings[%State] = "ForceClamp"
				DoForceClamp(FastMode=1)
				DoForceRamp(CenteredRamp_Settings,CenteredRamp_WaveNames)
				
			break
		EndSwitch
	endif  // FoundCenter
	
	If (!FoundCenter)  // If we haven't found the center, try again to find the center
		FineCentering_Settings[%CenterX_V]= FineCenterX[FineCenterIteration] 
		FineCentering_Settings[%CenterY_V]= FineCenterY[FineCenterIteration] 
		
		CFPSettings[%FineCenteringIteration]+=1
		CFP_MainLoop()
	Endif  // test == 1
	
End
Function MoveThenRampCallback()
	StopZFeedbackLoop()
	DoForceRamp(root:CFP:CenteredRamp_Settings,root:CFP:CenteredRamp_WaveNames)
End

Function StopZFeedbackLoop()
	// Here we stop the z feedback loop and reset it.  Without this code, our next force ramp will just be stuck.  
	td_stop()
	ir_StopPISLoop(-2)
	Struct ARFeedbackStruct FB
	ARGetFeedbackParms(FB,"outputZ")
	FB.StartEvent = "2"
	FB.StopEvent = "3"
	String ErrorStr
	ErrorStr += ir_writePIDSloop(FB)

End

// Center calculation happens here. 
// Currently does a quadratic fit but then just returns the current center position.  Will change this when we have a sample with molecules. 
Function CalculateCenterPosition(PosData,DefData)
	Wave DefData, PosData
	Duplicate/O DefData Quadratic_Fit
	Make/D/O/N=4 Quadratic_Coeff
	
	WaveStats/Q DefData
	Variable DefMin=V_min
	Variable ChangeInDef=V_max-V_min
	// Check to make sure that the minimum deflection signal is in the minimum 80% of the data.  
	Variable DefMinLoc=V_minRowLoc
	Variable StartRange=V_npnts*0.1
	Variable EndRange = V_npnts*0.9
	Variable MinInRange=(DefMinLoc>StartRange)&&(DefMinLoc<EndRange)
	// Default value for center location is the position associated with the minimum deflection signal. 
	Variable CenterLocation=PosData[DefMinLoc]
	// If the minimum deflection signal is in the minimum 80% of the data, then fit a parabola and get a better center value.
	If(MinInRange)
		WaveStats/Q PosData
		Variable PosAvg=V_min
		Variable ChangeInPos=V_max-V_min
		Variable DefOverPos=ChangeInDef/ChangeInPos
		
		Quadratic_Coeff[0] = DefMin
		Quadratic_Coeff[1] = DefOverPos
		Quadratic_Coeff[2] = DefOverPos
		Quadratic_Coeff[3] = PosAvg
		FuncFit/Q/N/NTHR=0/W=2 QuadraticFit Quadratic_Coeff DefData /X=PosData /D=Quadratic_Fit
		FuncFit/Q/N/NTHR=0/W=2 QuadraticFit Quadratic_Coeff DefData /X=PosData /D=Quadratic_Fit
		CenterLocation=Quadratic_Coeff[3]-(Quadratic_Coeff[1]/2/Quadratic_Coeff[2])
	EndIf
	Return CenterLocation
	
End //CalculateCenterPosition

// Custom Quadratic Fit Function.  Allows the center of the quadratic to vary, unlike to the stupid IGOR version
Function QuadraticFit(w,x) : FitFunc
	WAVE w
	Variable x

	return w[0]+w[1]*(x-w[3])+w[2]*(x-w[3])^2
End

///////////////////////////////////////////////////
// PauseCFPCallback()
// This will cause the program to end after the centered force pull.  All data will be saved, but you won't do anything else 
// Useful for modes where you want to pull from the center and then manually manipulate the molecule
//  such as for the RNA constructs (HIV stemloop and Sugar cane virus pseudoknot)

Function PauseCFPCallback()
	Wave/T CenteringSettings=root:CFP:CenteringSettings
	Beep
	StopZFeedbackLoop()  // Need this to stop feedback loop.  Fixed in version 7.1
	CenteringSettings[%$"EndProgram"]="1"
	CenteredForcePullCallback()
End

// CenteredForcePullCallback()
// This is the function that executes after the centered force ramp is finished, or after the the first ramp when no molecule is attached
// I am iterating the master loop and put the centered force pull data in the appropriate place
// This will end the master loop when the end master loop parameter is set to "Yes" or when we have reached the maximum number of iterations
Function CenteredForcePullCallback()
	Wave/T CenteringSettings=root:CFP:CenteringSettings
	Wave CFPSettings=root:CFP:CFPSettings

	CenteringSettings[%State] = "CenteredForcePullCallback"
	
	// Did we do a centered force ramp?
	Variable CenteredForceRamp=WhichListItem(CenteringSettings[%FoundCenterAction],"ForceRamp;RampThenClamp;RampThenPause;MoveThenForceRamp;")!=-1
	// If we did a centered force ramp, then save final force ramp with suffix _CFR (stands for centered force ramp)
	If(CenteredForceRamp)
		Wave DefVolts=root:CFP:DefV_Ramp2
		Wave ZSensorVolts = root:CFP:ZSensor_Ramp2
		String SaveName=CenteringSettings[%SaveName]+"_CFR"
		If(StringMatch(CenteringSettings[%FoundCenterAction],"MoveThenForceRamp"))
			ControlInfo/W=CFP_Panel LateralMoveSV
			Variable DistanceToMoveV=V_value
			String OffsetNote="CenterRampLateralOffset:"+num2str(DistanceToMoveV)+"\r"
			SaveAsAsylumForceRamp(SaveName,CFPSettings[%MasterIteration],DefVolts,ZSensorVolts,AdditionalNotes=OffsetNote)
		Else
			SaveAsAsylumForceRamp(SaveName,CFPSettings[%MasterIteration],DefVolts,ZSensorVolts)
		EndIf
		
	EndIf
	
	// Save Centering Data
	SaveCurrentData()
	
	// Set back to regular folder
	SetDataFolder root:CFP
	FinishCFP()
		
End //CenteredForcePullCallback

Function FinishCFP()
	// This is the code that will officially finish a centered force pull.  I'll add functionality to move around the surface here. 
	// I should also add code to reset all the appropriate wave values for the next centered force pull.
	// For now, it will just stop the program
	Wave/T CenteringSettings=root:CFP:CenteringSettings
	Wave CFPSettings=root:CFP:CFPSettings
	Wave/T ZeroThePDCallbackWave=root:ZeroThePD:ZeroThePDCallbackWave
	Wave/T CheckInvolsCallbackWave=root:CheckInvols:CheckInvolsCallbackWave

	CFPSettings[%MasterIteration]+=1
	// Max index for saving in the asylum format is 9999.  After that, we'll just reset to 0
	If(CFPSettings[%MasterIteration]>9999)
		CFPSettings[%MasterIteration]=0
	EndIf
	
	// If using the search grid, then use it.  If we found the center, then we found a molecule.
	// After moving to next spot, execute StartCFP()
	CenteringSettings[%State] = "FinishCFP"

	Variable EndProgram=StringMatch(CenteringSettings[%$"EndProgram"],"1")
	If(!EndProgram)
		If(CFPSettings[%UseSearchGrid]&&!CFPSettings[%UseZeroThePD]&&CFPSettings[%UseCheckInvols])
			CheckInvolsCallbackWave[%Callback]="StartCFP()"
			SearchForMolecule(FoundMolecule=CFPSettings[%FoundMolecule],Callback="DoCheckInvols()")
		EndIf
		If(CFPSettings[%UseSearchGrid]&&!CFPSettings[%UseZeroThePD]&&!CFPSettings[%UseCheckInvols])
			SearchForMolecule(FoundMolecule=CFPSettings[%FoundMolecule],Callback="StartCFP()")
		EndIf
		If(CFPSettings[%UseSearchGrid]&&CFPSettings[%UseZeroThePD]&&CFPSettings[%UseCheckInvols])
			ZeroThePDCallbackWave[%Callback]="DoCheckInvols()"
			CheckInvolsCallbackWave[%Callback]="StartCFP()"
			SearchForMolecule(FoundMolecule=CFPSettings[%FoundMolecule],Callback="DoZeroPD()")
		EndIf
		If(CFPSettings[%UseSearchGrid]&&CFPSettings[%UseZeroThePD]&&!CFPSettings[%UseCheckInvols])
			ZeroThePDCallbackWave[%Callback]="StartCFP()"
			SearchForMolecule(FoundMolecule=CFPSettings[%FoundMolecule],Callback="DoZeroPD()")
		EndIf
		If(!CFPSettings[%UseSearchGrid]&&CFPSettings[%UseZeroThePD]&&CFPSettings[%UseCheckInvols])
			ZeroThePDCallbackWave[%Callback]="DoCheckInvols()"
			CheckInvolsCallbackWave[%Callback]="StartCFP()"
			DoZeroPD()
		EndIf
		If(!CFPSettings[%UseSearchGrid]&&CFPSettings[%UseZeroThePD]&&!CFPSettings[%UseCheckInvols])
			ZeroThePDCallbackWave[%Callback]="StartCFP()"
			DoZeroPD()
		EndIf
		If(!CFPSettings[%UseSearchGrid]&&!CFPSettings[%UseZeroThePD]&&CFPSettings[%UseCheckInvols])
			CheckInvolsCallbackWave[%Callback]="StartCFP()"
			DoCheckInvols()		
		EndIf
		If(!CFPSettings[%UseSearchGrid]&&!CFPSettings[%UseZeroThePD]&&!CFPSettings[%UseCheckInvols])
			StartCFP()
		EndIf
	EndIF
	
End

Function SaveCurrentData()
	Wave/T CenteringSettings=root:CFP:CenteringSettings
	Wave CFPSettings=root:CFP:CFPSettings
	
	String CurrentIterationStr
	sprintf CurrentIterationStr, "%04d", CFPSettings[%MasterIteration]
	
	String DataFolderName="root:CFP:"+CenteringSettings[%SaveName]+CurrentIterationStr
	NewDataFolder/O $DataFolderName
	SetDataFolder root:CFP
	
	String WaveNames = WaveList("*", ";" ,"" )
	
	Variable NumWavesToCopy=ItemsInList(WaveNames, ";")
	Variable Counter=0
	For(Counter=0;Counter<NumWavesToCopy;Counter+=1)
		String CurrentWaveName=StringFromList(Counter, WaveNames)
		String NewWaveName=DataFolderName+":"+CurrentWaveName
		Duplicate/O $CurrentWaveName,$NewWaveName
	EndFor
								
End //SaveCurrentData

//////////////////////////////////////////////////////////////////////////
// Stuff for the user interface

Function/S CFPQuickSettingsList()
	Wave CFPQuickSettings=root:CFP:CFPQuickSettings
	Return GetWaveDimNames(CFPQuickSettings,DimNumber=1)
End

Function CFPTabProc(tca) : TabControl
	STRUCT WMTabControlAction &tca
	switch( tca.eventCode )
		case 2: // mouse up
			Variable tab = tca.tab
	
			SetVariable SurfaceTrigger1,disable= (tab!=0)
			SetVariable MoleculeTrigger1,disable= (tab!=0)
			SetVariable ApproachVelocity1,disable= (tab!=0)
			SetVariable RetractVelocity1,disable= (tab!=0)
			SetVariable DwellTime1,disable= (tab!=0)
			SetVariable NoTriggerDistance1,disable= (tab!=0)
			SetVariable ForceDistanceIFR,disable= (tab!=0)
			SetVariable SamplingRateIFR,disable= (tab!=0)
			SetVariable FilterFreqSV,disable= (tab!=0)
			SetVariable FirstRampCallbackSV,disable= (tab!=0)

			SetVariable SurfaceTrigger2,disable= (tab!=1)
			SetVariable MoleculeTrigger2,disable= (tab!=1)
			SetVariable ApproachVelocity2,disable= (tab!=1)
			SetVariable RetractVelocity2,disable= (tab!=1)
			SetVariable DwellTime2,disable= (tab!=1)
			SetVariable NoTriggerDistance2,disable= (tab!=1)
			SetVariable ForceDistanceCFR,disable= (tab!=1)
			SetVariable SamplingRateCFR,disable= (tab!=1)
			SetVariable CenteredRampCallbackSV,disable= (tab!=1)
			
			break
		case -1: // control being killed
			break
	endswitch

	return 0
End

Function CFPButtonProc(ba) : ButtonControl
	STRUCT WMButtonAction &ba
	String ButtonName=ba.CtrlName

	switch( ba.eventCode )
		case 2: // mouse up
			strswitch(ButtonName)
				case "CFPStartButton":
					StartCFP()
				break
				case "CFPStopButton":
					StopCFP()
				break 
			EndSwitch
		break
		case -1: // control being killed
			break
	endswitch

	return 0
End

Function CFPInfoDisplay(pa) : PopupMenuControl
	STRUCT WMPopupAction &pa

	switch( pa.eventCode )
		case 2: // mouse up
			Variable popNum = pa.popNum
			String popStr = pa.popStr
			DisplayCFPInfo(popStr)
			break
		case -1: // control being killed
			break
	endswitch

	return 0
End

Window CFP_Panel() : Panel
	PauseUpdate; Silent 1		// building window...
	NewPanel /K=1 /W=(963,57,1193,535) as "Centered Force Pull"
	ModifyPanel cbRGB=(56576,56576,56576)
	SetDrawLayer UserBack
	DrawLine 4,150,218,150
	DrawLine 4,309,218,309
	DrawLine 5,471,219,471
	Button CFPStartButton,pos={4,322},size={77,36},proc=CFPButtonProc,title="Start"
	Button CFPStartButton,fColor=(61440,61440,61440)
	SetVariable CenteringDistance,pos={4,78},size={171,16},title="Centering Distance"
	SetVariable CenteringDistance,format="%.1W1Pm"
	SetVariable CenteringDistance,limits={-inf,inf,5e-09},value= root:CFP:CFPSettings[%'Distance to move from center']
	SetVariable SurfaceTrigger2,pos={90,40},size={154,16},disable=1,title="Surface Trigger"
	SetVariable SurfaceTrigger2,format="\\JR%.1W1PN"
	SetVariable SurfaceTrigger2,limits={-inf,inf,1e-11},value= root:CFP:CenteredRamp_Settings[%'Surface Trigger'],styledText= 1
	SetVariable MoleculeTrigger2,pos={90,67},size={154,16},disable=1,title="Molecule Trigger"
	SetVariable MoleculeTrigger2,format="\\JR%.1W1PN"
	SetVariable MoleculeTrigger2,limits={-inf,inf,5e-12},value= root:CFP:CenteredRamp_Settings[%'Molecule Trigger'],styledText= 1
	SetVariable ApproachVelocity2,pos={84,94},size={160,16},disable=1,title="Approach Velocity"
	SetVariable ApproachVelocity2,format="\\JR%.1W1Pm/s"
	SetVariable ApproachVelocity2,limits={-inf,inf,1e-07},value= root:CFP:CenteredRamp_Settings[%'Approach Velocity'],styledText= 1
	SetVariable RetractVelocity2,pos={90,121},size={154,16},disable=1,title="Retract Velocity"
	SetVariable RetractVelocity2,format="\\JR%.1W1Pm/s"
	SetVariable RetractVelocity2,limits={-inf,inf,1e-07},value= root:CFP:CenteredRamp_Settings[%'Retract Velocity'],styledText= 1
	SetVariable DwellTime2,pos={90,148},size={154,16},disable=1,title="Surface Dwell Time"
	SetVariable DwellTime2,format="\\JR%.1W1Ps"
	SetVariable DwellTime2,limits={-inf,inf,0.5},value= root:CFP:CenteredRamp_Settings[%'Surface Dwell Time'],styledText= 1
	SetVariable NoTriggerDistance2,pos={67,175},size={177,16},disable=1,title="No Trigger Distance"
	SetVariable NoTriggerDistance2,format="\\JR%.1W1Pm"
	SetVariable NoTriggerDistance2,limits={-inf,inf,1e-08},value= root:CFP:CenteredRamp_Settings[%'No Trigger Distance'],styledText= 1
	SetVariable MaxIterations,pos={4,54},size={171,16},title="Fine Centering Max Iterations"
	SetVariable MaxIterations,value= root:CFP:CFPSettings[%'Max Iterations']
	Button CFPStopButton,pos={103,321},size={77,36},proc=CFPButtonProc,title="Stop"
	Button CFPStopButton,fColor=(61440,61440,61440)
	SetVariable CriticalFitDifference,pos={4,102},size={171,16},title="Critical Fit Difference"
	SetVariable CriticalFitDifference,format="%.1W1Pm"
	SetVariable CriticalFitDifference,limits={-inf,inf,1e-09},value= root:CFP:CFPSettings[%'Critical Fit Difference']
	PopupMenu InfoDisplay,pos={4,365},size={208,22},proc=CFPInfoDisplay,title="Display Info"
	PopupMenu InfoDisplay,mode=10,popvalue="PresetPullingVelocities",value= #"\"FirstRampTable;CenteringTable;CFPSettings;CircleSettings;FineCenteringSettings;SampleAtPointSettings;MoveToPointSettings;CenteredRampSettings;CurrentCenteringGraphs;PresetPullingVelocities;\""
	SetVariable SetCircleRadius,pos={4,31},size={171,16},title="Circle Radius"
	SetVariable SetCircleRadius,format="%.1W1Pm"
	SetVariable SetCircleRadius,limits={-inf,inf,5e-09},value= root:CFP:CFPSettings[%CircleRadius]
	SetVariable CurrentState,pos={4,4},size={217,24},title="Status",fSize=16
	SetVariable CurrentState,fStyle=1,valueColor=(65280,0,0)
	SetVariable CurrentState,value= root:CFP:CenteringSettings[%State]
	SetVariable TargetForce,pos={4,126},size={172,16},title="Target Force"
	SetVariable TargetForce,format="%.1W1PN"
	SetVariable TargetForce,limits={-inf,inf,5e-12},value= root:CFP:CFPSettings[%TargetForce]
	SetVariable Molecule,pos={4,201},size={196,16},title="Molecule"
	SetVariable Molecule,value= root:CFP:CenteringSettings[%Molecule]
	SetVariable ForceDistanceCFR,pos={65,202},size={179,16},disable=1,title="Force Distance"
	SetVariable ForceDistanceCFR,format="\\JR%.1W1Pm"
	SetVariable ForceDistanceCFR,limits={-inf,inf,1e-07},value= root:CFP:CenteredRamp_Settings[%'Extension Distance'],styledText= 1
	SetVariable SaveName,pos={4,221},size={218,16},proc=CheckSaveName,title="Save Name"
	SetVariable SaveName,value= root:CFP:CenteringSettings[%SaveName]
	SetVariable Iteration,pos={4,242},size={221,16},title="Iteration",format="%04d"
	SetVariable Iteration,limits={0,9999,1},value= root:CFP:CFPSettings[%MasterIteration]
	SetVariable SamplingRateCFR,pos={65,229},size={179,16},disable=1,title="Sample Rate"
	SetVariable SamplingRateCFR,format="\\JR%.1W1PHz"
	SetVariable SamplingRateCFR,limits={500,50000,1000},value= root:CFP:CenteredRamp_Settings[%'Sampling Rate'],styledText= 1
	CheckBox UseSearchGrid,pos={4,269},size={96,14},proc=CFPCheckProc,title="Use Search Grid"
	CheckBox UseSearchGrid,value= 1
	PopupMenu QuickSettings,pos={4,444},size={181,22},proc=CFPQuickSettingsMenu,title="Quick Settings"
	PopupMenu QuickSettings,mode=6,popvalue="650nmDigDNA",value= #"CFPQuickSettingsList()"
	SetVariable CenteredRampCallbackSV,pos={44,256},size={200,16},disable=1,title="Callback"
	SetVariable CenteredRampCallbackSV,limits={500,50000,1000},value= root:CFP:CenteredRamp_WaveNames[%Callback]
	PopupMenu CenteringMode,pos={4,391},size={178,22},proc=CFPCenteringModePopMenuProc,title="Centering Mode"
	PopupMenu CenteringMode,mode=1,popvalue="FullCentering",value= #"\"FullCentering;JustFineCentering;\""
	PopupMenu FoundCenterActionMenu,pos={4,417},size={190,22},proc=FoundCenterActionPopMenuProc,title="Found Center Action"
	PopupMenu FoundCenterActionMenu,mode=1,popvalue="ForceRamp",value= #"\"ForceRamp;RampThenClamp;ForceClamp;RampThenPause;Pause;ForceRampCustomCallback;MoveThenForceRamp\""
	SetVariable CenteringModeSV,pos={4,180},size={196,16},title="Centering Mode"
	SetVariable CenteringModeSV,value= root:CFP:CenteringSettings[%CenteringMode]
	SetVariable FoundCenterAction,pos={4,160},size={196,16},title="Found Center Action"
	SetVariable FoundCenterAction,value= root:CFP:CenteringSettings[%FoundCenterAction]
	CheckBox UseZeroThePD_CB,pos={116,269},size={102,14},proc=CFPCheckProc,title="Use Zero The PD"
	CheckBox UseZeroThePD_CB,value= 1
	SetVariable LateralMoveSV,pos={2,478},size={181,16},title="Lateral Move Distance"
	SetVariable LateralMoveSV,help={"This will offset a distance from the center in the lateral direction for the final force ramp.  Only works with MoveThenForceRamp mode.  Don't use this for most things."}
	SetVariable LateralMoveSV,format="%.2W1Pm",limits={-inf,inf,5e-08},value= _NUM:0
	CheckBox UseCheckInvols_CB,pos={6,291},size={102,14},proc=CFPCheckProc,title="Use Check Invols"
	CheckBox UseCheckInvols_CB,value= 1
	CheckBox UsePresetPV_CB,pos={116,292},size={108,14},proc=CFPCheckProc,title="Use Preset Pull Vel"
	CheckBox UsePresetPV_CB,value= 0
EndMacro

Function CheckSaveName(sva) : SetVariableControl
	STRUCT WMSetVariableAction &sva

	switch( sva.eventCode )
		case 1: // mouse up
		case 2: // Enter key
		case 3: // Live update
			Variable dval = sva.dval
			String sval = sva.sval
				Variable NameLength=strlen(sval)
				If(NameLength>13)
					Wave/T CenteringSettings= root:CFP:CenteringSettings
					String NewName=sval[0,12]
					CenteringSettings[%SaveName]=NewName
					
				EndIf
			
			break
		case -1: // control being killed
			break
	endswitch

	return 0
End

Function CFPCheckProc(cba) : CheckBoxControl
	STRUCT WMCheckboxAction &cba
	String CheckBoxName=cba.CtrlName
	Wave CFPSettings=root:CFP:CFPSettings
	

	switch( cba.eventCode )
		case 2: // mouse up
			Variable checked = cba.checked
			strswitch(CheckBoxName)
				case "UseSearchGrid":
					CFPSettings[%UseSearchGrid]=Checked
				break
				case "UseZeroThePD_CB":
					CFPSettings[%UseZeroThePD]=Checked
				break
				case "UseCheckInvols_CB":
					CFPSettings[%UseCheckInvols]=Checked
				break
				case "UsePresetPV_CB":
					CFPSettings[%UsePresetPullingVelocities]=Checked
				break
				
			EndSwitch
			break
		case -1: // control being killed
			break
	endswitch

	return 0
End

Function CFPQuickSettingsMenu(pa) : PopupMenuControl
	STRUCT WMPopupAction &pa
	
	Wave FirstRamp_QuickSettings=root:CFP:FirstRamp_QuickSettings
	Wave/T FirstRamp_WaveNamesQS=root:CFP:FirstRamp_WaveNamesQS
	Wave CenteredRamp_QuickSettings=root:CFP:CenteredRamp_QuickSettings
	Wave/T CenteredRamp_WaveNamesQS=root:CFP:CenteredRamp_WaveNamesQS
	Wave CFPQuickSettings=root:CFP:CFPQuickSettings
	Wave/T CenteringQuickSettings=root:CFP:CenteringQuickSettings
	SetDataFolder root:CFP
	switch( pa.eventCode )
		case 2: // mouse up
			Variable popNum = pa.popNum
			String SelectedQS = pa.popStr

			Duplicate/O/R=[0,*][popNum-1] FirstRamp_QuickSettings,FirstRamp_Settings
			Redimension/N=-1 CFPSettings
			Duplicate/O/R=[0,*][popNum-1] FirstRamp_WaveNamesQS,FirstRamp_WaveNames
			Redimension/N=-1 FirstRamp_WaveNames
			Duplicate/O/R=[0,*][popNum-1] CenteredRamp_QuickSettings,CenteredRamp_Settings
			Redimension/N=-1 CenteredRamp_Settings
			Duplicate/O/R=[0,*][popNum-1] CenteredRamp_WaveNamesQS,CenteredRamp_WaveNames
			Redimension/N=-1 CenteredRamp_WaveNames
			Duplicate/O/R=[0,*][popNum-1] CenteringQuickSettings,CenteringSettings
			Redimension/N=-1 CenteringSettings
			Duplicate/O/R=[0,*][popNum-1] CFPQuickSettings,CFPSettings
			Redimension/N=-1 CFPSettings
			UpdateCFPMenus()

			break
		case -1: // control being killed
			break
	endswitch

	return 0
End

Function CFPCenteringModePopMenuProc(pa) : PopupMenuControl
	STRUCT WMPopupAction &pa

	switch( pa.eventCode )
		case 2: // mouse up
			Variable popNum = pa.popNum
			String popStr = pa.popStr
			Wave/T CenteringSettings=root:CFP:CenteringSettings
			CenteringSettings[%CenteringMode]=popStr			
			break
		case -1: // control being killed
			break
	endswitch

	return 0
End

Function UpdateCFPMenus()
	Wave/T CenteringSettings=root:CFP:CenteringSettings
	PopupMenu CenteringMode,popvalue=CenteringSettings[%CenteringMode]
	PopupMenu FoundCenterActionMenu,popvalue=CenteringSettings[%FoundCenterAction]
	
End

Function FoundCenterActionPopMenuProc(pa) : PopupMenuControl
	STRUCT WMPopupAction &pa

	switch( pa.eventCode )
		case 2: // mouse up
			Variable popNum = pa.popNum
			String popStr = pa.popStr
			Wave/T CenteringSettings=root:CFP:CenteringSettings
			CenteringSettings[%FoundCenterAction]=popStr

			break
		case -1: // control being killed
			break
	endswitch

	return 0
End