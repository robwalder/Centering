#pragma rtGlobals=3		// Use modern global access method and strict wave access.
#include "::AR-Data:ARForceData"

Window CFPReport() : Panel
	PauseUpdate; Silent 1		// building window...
	NewPanel /W=(704,103,1027,384) as "CFP Report"
	ShowTools/A
	ListBox CFP_List,pos={15,9},size={84,221}
	ListBox CFPDisplay_List,pos={123,9},size={84,221}
	Button ShowStandard_Button,pos={220,9},size={94,34},title="Show Standard"
	Button ShowSelected_Button1,pos={220,55},size={94,34},title="Show Selected"
	CheckBox CFPAll_CB,pos={15,236},size={29,14},title="All",value= 0,mode=1
	CheckBox CFPFullCentering_CB,pos={15,254},size={82,14},title="Full Centering"
	CheckBox CFPFullCentering_CB,value= 0,mode=1
EndMacro

Function/S CenteringWaveNote(CFPName,[DateString,CenteringVersion,MoleculeName])
	String CFPName,DateString,MoleculeName
	Variable CenteringVersion
	
	// Date string needs to be in format yyyy-mm-dd
	If(ParamIsDefault(DateString))
		DateString="2015-00-00"
	EndIf	
	If(ParamIsDefault(CenteringVersion))
		CenteringVersion=7.1
	EndIf
	
	If(ParamIsDefault(MoleculeName))
		MoleculeName="Unknown"
	EndIf
	String NewWaveNotes="Date:"+DateString+"\r"
	
	Variable EndNameIndex=strlen(CFPName)
	Variable Iteration=str2num(CFPName[EndNameIndex-4,EndNameIndex])
	
	Wave CFPStats=$("root:CFP:SavedData:CFPStats_"+num2str(iteration))
	NewWaveNotes+="XYCenterDistance:"+num2str(CFPLateralDistance(CFPFullNameToCenterName(CFPName)))+"\r"
	NewWaveNotes+="ZTipAttachmentDistance:Nan"+"\r"
	NewWaveNotes+="CenteringVersion:"+num2str(CenteringVersion)+"\r"
	NewWaveNotes+="CenteringIteration:"+num2str(Iteration)+"\r"
	NewWaveNotes+="MoleculeName:"+MoleculeName+"\r"
	NewWaveNotes+="OriginalName:"+CFPName+"\r"
	Return NewWaveNotes
End


Function DisplayReport(CFPName)
	String CFPName
	String TargetDirectory="root:CFP"
	If(!StringMatch("Current",CFPName))
		TargetDirectory+=":"+CFPName
	EndIf

	DoWindow $(CFPName+"_Circle")
	If(!V_flag)	
		Display/K=1/N= $(CFPName+"_Circle") $(TargetDirectory+":ZSensorCircle") 
		Label bottom "Time (s)"
		Label left "Z Sensor (nm)"		
		ModifyGraph mode=3,rgb=(0,0,0 ),muloffset={0,1e9*GV("ZLVDTSens")}, tickUnit=1

	EndIf
	
	Wave CFPSettings=$(TargetDirectory+":CFPSettings")
	If(CFPSettings[%StepIteration]>0)
		DoWindow $(CFPName+"_Steps")
		String RangeString="[1,"+num2str(CFPSettings[%StepIteration])+"]"
		Wave ZTargets=$(TargetDirectory+":ZTargets")
		Wave XTargets =$(TargetDirectory+":XTargets")
		Wave YTargets=$(TargetDirectory+":YTargets")
		If(!V_flag)	
			Display/K=1/N=$(CFPName+"_Steps") ZTargets[1,CFPSettings[%StepIteration]-1] vs XTargets[1,CFPSettings[%StepIteration]-1]
			AppendToGraph/T ZTargets[1,CFPSettings[%StepIteration]-1] vs YTargets[1,CFPSettings[%StepIteration]-1]
			Variable XDirection=(XTargets[2]-XTargets[1])>0
			Variable YDirection=(YTargets[2]-YTargets[1])>0
			
			If(XDirection!=YDirection)
				SetAxis/A/R top
			EndIf
			ModifyGraph mode=4,rgb=(0,0,0 ),tickUnit=1,muloffset[0]={1e9*GV("XLVDTSens"),1e9*GV("ZLVDTSens")},muloffset[1]={1e9*GV("YLVDTSens"),1e9*GV("ZLVDTSens")}
			

			Label bottom "X Sensor (nm)"
			Label left "Z Sensor (nm)"
			Label top "Y Sensor (nm)"
		EndIf
	EndIf // Steps
	
	
	If(CFPSettings[%FineCenteringIteration]>0)
		DoWindow $(CFPName+"_FineCenteringX")
		Variable FineCounter=0
		If(!V_flag)	
			Display/K=1/N= $(CFPName+"_FineCenteringX") $(TargetDirectory+":ZSensorX_0") vs $(TargetDirectory+":XPos_0")
			ModifyGraph mode[0]=3,rgb[0]=(0,65000,0 ),tickUnit=1,muloffset[0]={1e9*GV("XLVDTSens"),1e9*GV("ZLVDTSens")}
			AppendToGraph $(TargetDirectory+":XFit_0") vs $(TargetDirectory+":XPos_0")
			ModifyGraph mode[1]=0,rgb[1]=(0,0,0 ),tickUnit=1,muloffset[1]={1e9*GV("XLVDTSens"),1e9*GV("ZLVDTSens")}
			Label left "Z Sensor"
			Label bottom "X Sensor"

			For(FineCounter=1;FineCounter<CFPSettings[%FineCenteringIteration]+1;FineCounter+=1)
				AppendToGraph $(TargetDirectory+":ZSensorX_"+num2str(FineCounter)) vs $(TargetDirectory+":XPos_"+num2str(FineCounter))
				ModifyGraph mode[2*FineCounter]=3,rgb[2*FineCounter]=(0,65000,0 ),tickUnit=1,muloffset[2*FineCounter]={1e9*GV("XLVDTSens"),1e9*GV("ZLVDTSens")}

				AppendToGraph $(TargetDirectory+":XFit_"+num2str(FineCounter)) vs $(TargetDirectory+":XPos_"+num2str(FineCounter))
				ModifyGraph mode[2*FineCounter+1]=0,rgb[2*FineCounter+1]=(0,0,0 ),tickUnit=1,muloffset[2*FineCounter+1]={1e9*GV("XLVDTSens"),1e9*GV("ZLVDTSens")}
			EndFor
		EndIf
		
		DoWindow $(CFPName+"_FineCenteringY")
		If(!V_flag)	
			Display/K=1/N= $(CFPName+"_FineCenteringY") $(TargetDirectory+":ZSensorY_0") vs $(TargetDirectory+":YPos_0")
			ModifyGraph mode[0]=3,rgb[0]=(0,65000,0 ),tickUnit=1,muloffset[0]={1e9*GV("YLVDTSens"),1e9*GV("ZLVDTSens")}
			AppendToGraph $(TargetDirectory+":YFit_0") vs $(TargetDirectory+":YPos_0")
			ModifyGraph mode[1]=0,rgb[1]=(0,0,0 ),tickUnit=1,muloffset[1]={1e9*GV("YLVDTSens"),1e9*GV("ZLVDTSens")}
			Label left "Z Sensor"
			Label bottom "Y Sensor"

			For(FineCounter=1;FineCounter<CFPSettings[%FineCenteringIteration]+1;FineCounter+=1)
				AppendToGraph $(TargetDirectory+":ZSensorY_"+num2str(FineCounter)) vs $(TargetDirectory+":YPos_"+num2str(FineCounter))
				ModifyGraph mode[2*FineCounter]=3,rgb[2*FineCounter]=(0,65000,0 ),tickUnit=1,muloffset[2*FineCounter]={1e9*GV("YLVDTSens"),1e9*GV("ZLVDTSens")}

				AppendToGraph $(TargetDirectory+":YFit_"+num2str(FineCounter)) vs $(TargetDirectory+":YPos_"+num2str(FineCounter))
				ModifyGraph mode[2*FineCounter+1]=0,rgb[2*FineCounter+1]=(0,0,0 ),tickUnit=1,muloffset[2*FineCounter+1]={1e9*GV("YLVDTSens"),1e9*GV("ZLVDTSens")}
			EndFor
		EndIf
	EndIf // Steps
	
	DoWindow $(CFPName+"_PathToCenter")
	If(!V_flag)	
		Display/K=1/N=$(CFPName+"_PathToCenter") $(TargetDirectory+":Circles_Y") vs $(TargetDirectory+":Circles_X") 
		Label bottom "X Sensor"
		Label left "Y Sensor"		
		ModifyGraph mode[0]=3,rgb[0]=(0,0,0),marker[0]=8

	 	If(CFPSettings[%StepIteration]>0)
			AppendToGraph YTargets[3,CFPSettings[%StepIteration]-1] vs XTargets[3,CFPSettings[%StepIteration]-1]
			ModifyGraph mode[1]=3,rgb[1]=(0,65000,0),marker[1]=1
		EndIf
		
		If(CFPSettings[%FineCenteringIteration]>0)
				Wave FineCenterY=$(TargetDirectory+":FineCenterY")
				Wave FineCenterX=$(TargetDirectory+":FineCenterX")
				AppendToGraph FineCenterY[0,CFPSettings[%FineCenteringIteration]] vs FineCenterX[0,CFPSettings[%FineCenteringIteration]]
				ModifyGraph mode[2]=3,rgb[2]=(0,0,65000),marker[2]=0
		EndIf
		
	EndIf
	
End

// Determine the distance of the lateral offset from the center location
Function LateralOffsetFromCenter(CFPFullName)
	String CFPFullName
	
	String CFPName=CFPFullNameToCenterName(CFPFullName)
	
	String TargetDirectory="root:CFP"
	If(!StringMatch("Current",CFPName))
		TargetDirectory+=":"+CFPName
	EndIf
	
	// Replace this with x and y for force pull
	//ApplyFuncsToForceWaves("GetLVDTPosition(ForceWave,\"X\");GetLVDTPosition(ForceWave,\"Y\")",FPList=CFPFullName,OutputWaveNameList="XPosTemp;YPosTemp",NumOutputs="1;1")
	ApplyFuncsToForceWaves("GetLVDTV(ForceWave,\"X\");GetLVDTV(ForceWave,\"Y\");GetLVDTSens(ForceWave,\"X\");GetLVDTSens(ForceWave,\"Y\")",FPList=CFPFullName,OutputWaveNameList="XPosTemp;YPosTemp;XSensTemp;YSensTemp",NumOutputs="1;1;1;1")
	Wave XPosTemp
	Wave YPosTemp
	Wave XSensTemp
	Wave YSensTemp
	
	Wave CFPSettings=$(TargetDirectory+":CFPSettings")
	
	If(CFPSettings[%'Center Found?'])
		Wave FineCenterY=$(TargetDirectory+":FineCenterY")
		Wave FineCenterX=$(TargetDirectory+":FineCenterX")
//		Variable CenterXPos=(FineCenterX[CFPSettings[%FineCenteringIteration]]+GV("XLVDTOFfset"))*GV("XLVDTSens")
//		Variable CenterYPos=(FineCenterY[CFPSettings[%FineCenteringIteration]]+GV("YLVDTOFfset"))*GV("YLVDTSens")
		Variable CenterXPos=FineCenterX[CFPSettings[%FineCenteringIteration]]
		Variable CenterYPos=FineCenterY[CFPSettings[%FineCenteringIteration]]
//		Variable DistanceX=Abs(CenterXPos-XPosTemp[0])
//		Variable DistanceY=Abs(CenterYPos-YPosTemp[0])
		Variable DistanceX=Abs(CenterXPos-XPosTemp[0])*XSensTemp[0]
		Variable DistanceY=Abs(CenterYPos-YPosTemp[0])*YSensTemp[0]
		Return sqrt(DistanceX^2+DistanceY^2)
	Else
		Return Nan
	EndIf
End


Function/S CFPFullNameToCenterName(CFPFullName)
	String CFPFullName
	Variable EndIndex=strlen(CFPFullName)
	String CFPName=CFPFullName[0,EndIndex-9]+CFPFullName[EndIndex-4,EndIndex]
	Return CFPName
End

Function CFPFullName_LD(FRName)
	String FRName
	Return CFPLateralDistance(CFPFullNameToCenterName(FRName))
End

Function CFPLateralDistance(CFPName)
	String CFPName
	String TargetDirectory="root:CFP"
	If(!StringMatch("Current",CFPName))
		TargetDirectory+=":"+CFPName
	EndIf
	
	Wave StartXWave=$(TargetDirectory+":Circles_X")
	Wave StartYWave=$(TargetDirectory+":Circles_Y")
	
	Wave CFPSettings=$(TargetDirectory+":CFPSettings")
	
	If(CFPSettings[%'Center Found?'])
		Wave FineCenterY=$(TargetDirectory+":FineCenterY")
		Wave FineCenterX=$(TargetDirectory+":FineCenterX")
		Variable DistanceX=Abs(FineCenterX[CFPSettings[%FineCenteringIteration]]-StartXWave[0])*GV("XLVDTSens")
		Variable DistanceY=Abs(FineCenterY[CFPSettings[%FineCenteringIteration]]-StartYWave[0])*GV("YLVDTSens")
		Return sqrt(DistanceX^2+DistanceY^2)
	Else
		Return Nan
	EndIf

End