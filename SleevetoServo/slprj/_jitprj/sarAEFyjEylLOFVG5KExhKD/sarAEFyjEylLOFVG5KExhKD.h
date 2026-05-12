#pragma once

#ifdef __cplusplus
#define EXTERN_C_CC extern "C"
#else
#define EXTERN_C_CC
#endif

#if defined _WIN32
#define DLL_EXPORT_CC EXTERN_C_CC __declspec(dllexport)
#elif __GNUC__ >= 4
#define DLL_EXPORT_CC EXTERN_C_CC  __attribute__ ((visibility ("default")))
#else
#define DLL_EXPORT_CC EXTERN_C_CC
#endif


/* Type Definitions */
#ifndef typedef_gvar_instance
#define typedef_gvar_instance
typedef struct
{
    uint8_T c1_JITStateAnimation[1];
    real_T *c1_u;
    real_T (*c1_out)[3];
    uint8_T c1_JITTransitionAnimation[1];
    emlrtMCInfo c1_b_emlrtMCI;
    emlrtRSInfo c1_b_emlrtRSI;
    emlrtMCInfo c1_c_emlrtMCI;
    emlrtRSInfo c1_c_emlrtRSI;
    emlrtMCInfo c1_d_emlrtMCI;
    emlrtRSInfo c1_d_emlrtRSI;
    emlrtMCInfo c1_e_emlrtMCI;
    emlrtRSInfo c1_e_emlrtRSI;
    emlrtMCInfo c1_emlrtMCI;
    emlrtRSInfo c1_emlrtRSI;
    void *c1_fEmlrtCtx;
    emlrtMCInfo c1_f_emlrtMCI;
    emlrtRSInfo c1_f_emlrtRSI;
    emlrtRSInfo c1_g_emlrtRSI;
    emlrtRSInfo c1_h_emlrtRSI;
    emlrtRSInfo c1_i_emlrtRSI;
} gvar_instance;
#endif /* typedef_gvar_instance */

/* Named Constants */

/* Variable Declarations */

/* Variable Definitions */

/* Function Declarations */
DLL_EXPORT_CC void initialize_c1_ArmCalibV2(SimStruct *S, gvar_instance *ptr_gvar_instance);
DLL_EXPORT_CC void initialize_params_c1_ArmCalibV2(SimStruct *S, gvar_instance *ptr_gvar_instance);
DLL_EXPORT_CC void mdl_start_c1_ArmCalibV2(SimStruct *S, gvar_instance *ptr_gvar_instance);
DLL_EXPORT_CC void mdl_terminate_c1_ArmCalibV2(SimStruct *S, gvar_instance *ptr_gvar_instance);
DLL_EXPORT_CC void mdl_setup_runtime_resources_c1_ArmCalibV2(SimStruct *S, gvar_instance *ptr_gvar_instance);
DLL_EXPORT_CC void mdl_cleanup_runtime_resources_c1_ArmCalibV2(SimStruct *S, gvar_instance *ptr_gvar_instance);
DLL_EXPORT_CC void enable_c1_ArmCalibV2(SimStruct *S, gvar_instance *ptr_gvar_instance);
DLL_EXPORT_CC void disable_c1_ArmCalibV2(SimStruct *S, gvar_instance *ptr_gvar_instance);
DLL_EXPORT_CC void sf_gateway_c1_ArmCalibV2(SimStruct *S, gvar_instance *ptr_gvar_instance);
DLL_EXPORT_CC void ext_mode_exec_c1_ArmCalibV2(SimStruct *S, gvar_instance *ptr_gvar_instance);
DLL_EXPORT_CC const mxArray *get_sim_state_c1_ArmCalibV2(SimStruct *S, gvar_instance *ptr_gvar_instance);
DLL_EXPORT_CC void set_sim_state_c1_ArmCalibV2(SimStruct *S, gvar_instance *ptr_gvar_instance, const mxArray *c1_st);
DLL_EXPORT_CC void c1_emlrt_marshallIn(SimStruct *S, gvar_instance *ptr_gvar_instance, const mxArray *c1_nullptr, const char_T *c1_identifier, real_T c1_y[3]);
DLL_EXPORT_CC void c1_b_emlrt_marshallIn(SimStruct *S, gvar_instance *ptr_gvar_instance, const mxArray *c1_b_u, const emlrtMsgIdentifier *c1_parentId, real_T c1_y[3]);
DLL_EXPORT_CC void init_dsm_address_info(SimStruct *S, gvar_instance *ptr_gvar_instance);
DLL_EXPORT_CC void init_simulink_io_address(SimStruct *S, gvar_instance *ptr_gvar_instance);
DLL_EXPORT_CC void JIT_release_mem_fcn(gvar_instance *ptr_gvar_instance);
DLL_EXPORT_CC gvar_instance *JIT_init_mem_fcn(void);

/* Function Definitions */

