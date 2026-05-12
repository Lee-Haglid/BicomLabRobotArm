#define S_FUNCTION_NAME sf_sfun
#include "covrt.h"
#include "cgxert.h"
#include "emlrt.h"
#include "sfrtif/sfc_sf.h"
#include "sfrtif/MessageServiceLayer.h"
#include "sfrtif/DebuggerRuntimeInterface.h"
#include "sfrtif/sfc_mex.h"
#include "sfrtif/sf_runtime_errors.h"
#include "sfrtif/sf_partitioning_execution_bridge.h"
#include "rtwtypes.h"
#include "simtarget/slSimTgtClientServerAPIBridge.h"
#include "sfrtif/sfc_sdi.h"
#include "sfrtif/sf_test_language.h"
#include "simlogCIntrf.h"
#include "half_type.h"
#include "multiword_types.h"
#include "sfrtif/sfc_messages.h"
#include "slccrt.h"
#include "sl_sfcn_cov/sl_sfcn_cov_bridge.h"
#include "mwstringutil.h"
#include "blas.h"
#include "lapacke.h"
#include "sarAEFyjEylLOFVG5KExhKD.h"
#include <stdio.h>

#define rtInf (mxGetInf())
#define rtMinusInf (-(mxGetInf()))
#define rtNaN (mxGetNaN())
#define rtInfF ((real32_T)mxGetInf())
#define rtMinusInfF (-(real32_T)mxGetInf())
#define rtNaNF ((real32_T)mxGetNaN())
#define rtIsNaN(X) ((int)mxIsNaN(X))
#define rtIsInf(X) ((int)mxIsInf(X))
#ifdef utFree
#undef utFree
#endif
#ifdef utMalloc
#undef utMalloc
#endif
#ifdef __cplusplus
extern "C" void* utMalloc(size_t size);
extern "C" void utFree(void*);
#else
extern void* utMalloc(size_t size);
extern void utFree(void*);
#endif


/* Type Definitions */
#ifndef c1_struct_c1_tag_sc6f4Behc0Ffg9eeZ0XliHC
#define c1_struct_c1_tag_sc6f4Behc0Ffg9eeZ0XliHC
struct c1_tag_sc6f4Behc0Ffg9eeZ0XliHC
{
    uint32_T dim;
    uint32_T nanflag;
    uint32_T linear;
    uint32_T ComparisonMethod;
};
#endif /* c1_struct_c1_tag_sc6f4Behc0Ffg9eeZ0XliHC */
#ifndef c1_typedef_c1_sc6f4Behc0Ffg9eeZ0XliHC
#define c1_typedef_c1_sc6f4Behc0Ffg9eeZ0XliHC
typedef struct c1_tag_sc6f4Behc0Ffg9eeZ0XliHC c1_sc6f4Behc0Ffg9eeZ0XliHC;
#endif /* c1_typedef_c1_sc6f4Behc0Ffg9eeZ0XliHC */
#ifndef c1_struct_c1_tag_CwmmLJkcNIjs9slqeIYe7B
#define c1_struct_c1_tag_CwmmLJkcNIjs9slqeIYe7B
struct c1_tag_CwmmLJkcNIjs9slqeIYe7B
{
    real_T f1;
    int32_T f2;
};
#endif /* c1_struct_c1_tag_CwmmLJkcNIjs9slqeIYe7B */
#ifndef c1_typedef_c1_cell_0
#define c1_typedef_c1_cell_0
typedef struct c1_tag_CwmmLJkcNIjs9slqeIYe7B c1_cell_0;
#endif /* c1_typedef_c1_cell_0 */
#ifndef c1_struct_c1_tag_IXZbk4aPjQFR6fO0q1hmvH
#define c1_struct_c1_tag_IXZbk4aPjQFR6fO0q1hmvH
struct c1_tag_IXZbk4aPjQFR6fO0q1hmvH
{
    int32_T __dummy;
};
#endif /* c1_struct_c1_tag_IXZbk4aPjQFR6fO0q1hmvH */
#ifndef c1_typedef_c1_rtString_2
#define c1_typedef_c1_rtString_2
typedef struct c1_tag_IXZbk4aPjQFR6fO0q1hmvH c1_rtString_2;
#endif /* c1_typedef_c1_rtString_2 */
#ifndef c1_struct_c1_tag_sHXilLztTi0iLvS7fZEsGE
#define c1_struct_c1_tag_sHXilLztTi0iLvS7fZEsGE
struct c1_tag_sHXilLztTi0iLvS7fZEsGE
{
    c1_cell_0 _data;
};
#endif /* c1_struct_c1_tag_sHXilLztTi0iLvS7fZEsGE */
#ifndef c1_typedef_c1_s_sHXilLztTi0iLvS7fZEsGE
#define c1_typedef_c1_s_sHXilLztTi0iLvS7fZEsGE
typedef struct c1_tag_sHXilLztTi0iLvS7fZEsGE c1_s_sHXilLztTi0iLvS7fZEsGE;
#endif /* c1_typedef_c1_s_sHXilLztTi0iLvS7fZEsGE */
#ifndef c1_struct_c1_tag_s7x1Wx46WFovLWMRmX2SU0C
#define c1_struct_c1_tag_s7x1Wx46WFovLWMRmX2SU0C
struct c1_tag_s7x1Wx46WFovLWMRmX2SU0C
{
    char_T struct_tm[7];
    char_T struct_timespec[13];
};
#endif /* c1_struct_c1_tag_s7x1Wx46WFovLWMRmX2SU0C */
#ifndef c1_typedef_c1_s7x1Wx46WFovLWMRmX2SU0C
#define c1_typedef_c1_s7x1Wx46WFovLWMRmX2SU0C
typedef struct c1_tag_s7x1Wx46WFovLWMRmX2SU0C c1_s7x1Wx46WFovLWMRmX2SU0C;
#endif /* c1_typedef_c1_s7x1Wx46WFovLWMRmX2SU0C */
#ifndef c1_struct_c1_tag_smzGQHcQ1fZcSCW5rtLpn4F
#define c1_struct_c1_tag_smzGQHcQ1fZcSCW5rtLpn4F
struct c1_tag_smzGQHcQ1fZcSCW5rtLpn4F
{
    boolean_T CaseSensitivity;
    char_T PartialMatching[6];
    boolean_T StructExpand;
    boolean_T IgnoreNulls;
    boolean_T SupportOverrides;
};
#endif /* c1_struct_c1_tag_smzGQHcQ1fZcSCW5rtLpn4F */
#ifndef c1_typedef_c1_smzGQHcQ1fZcSCW5rtLpn4F
#define c1_typedef_c1_smzGQHcQ1fZcSCW5rtLpn4F
typedef struct c1_tag_smzGQHcQ1fZcSCW5rtLpn4F c1_smzGQHcQ1fZcSCW5rtLpn4F;
#endif /* c1_typedef_c1_smzGQHcQ1fZcSCW5rtLpn4F */
#ifndef c1_struct_c1_tag_FDrX8kOEjZXLXru8nW4swE
#define c1_struct_c1_tag_FDrX8kOEjZXLXru8nW4swE
struct c1_tag_FDrX8kOEjZXLXru8nW4swE
{
    char_T f1[6];
    char_T f2[6];
};
#endif /* c1_struct_c1_tag_FDrX8kOEjZXLXru8nW4swE */
#ifndef c1_typedef_c1_s_FDrX8kOEjZXLXru8nW4swE
#define c1_typedef_c1_s_FDrX8kOEjZXLXru8nW4swE
typedef struct c1_tag_FDrX8kOEjZXLXru8nW4swE c1_s_FDrX8kOEjZXLXru8nW4swE;
#endif /* c1_typedef_c1_s_FDrX8kOEjZXLXru8nW4swE */
#ifndef c1_struct_c1_tag_SvAQu5Z41uhzWczF5Op4iF
#define c1_struct_c1_tag_SvAQu5Z41uhzWczF5Op4iF
struct c1_tag_SvAQu5Z41uhzWczF5Op4iF
{
    char_T Value[6];
};
#endif /* c1_struct_c1_tag_SvAQu5Z41uhzWczF5Op4iF */
#ifndef c1_typedef_c1_s_SvAQu5Z41uhzWczF5Op4iF
#define c1_typedef_c1_s_SvAQu5Z41uhzWczF5Op4iF
typedef struct c1_tag_SvAQu5Z41uhzWczF5Op4iF c1_s_SvAQu5Z41uhzWczF5Op4iF;
#endif /* c1_typedef_c1_s_SvAQu5Z41uhzWczF5Op4iF */
#ifndef c1_struct_c1_tag_iausgUa9Tcm9fmfau0mSIH
#define c1_struct_c1_tag_iausgUa9Tcm9fmfau0mSIH
struct c1_tag_iausgUa9Tcm9fmfau0mSIH
{
    char_T Value[6];
};
#endif /* c1_struct_c1_tag_iausgUa9Tcm9fmfau0mSIH */
#ifndef c1_typedef_c1_s_iausgUa9Tcm9fmfau0mSIH
#define c1_typedef_c1_s_iausgUa9Tcm9fmfau0mSIH
typedef struct c1_tag_iausgUa9Tcm9fmfau0mSIH c1_s_iausgUa9Tcm9fmfau0mSIH;
#endif /* c1_typedef_c1_s_iausgUa9Tcm9fmfau0mSIH */
#ifndef c1_struct_c1_tag_xOZlLoGvSrTJr14RWwCqHG
#define c1_struct_c1_tag_xOZlLoGvSrTJr14RWwCqHG
struct c1_tag_xOZlLoGvSrTJr14RWwCqHG
{
    char_T f1[3];
    char_T f2[7];
    char_T f3[6];
};
#endif /* c1_struct_c1_tag_xOZlLoGvSrTJr14RWwCqHG */
#ifndef c1_typedef_c1_cell_3
#define c1_typedef_c1_cell_3
typedef struct c1_tag_xOZlLoGvSrTJr14RWwCqHG c1_cell_3;
#endif /* c1_typedef_c1_cell_3 */
#ifndef c1_struct_c1_tag_6jR4RtbHdjyG00WYqgD5nF
#define c1_struct_c1_tag_6jR4RtbHdjyG00WYqgD5nF
struct c1_tag_6jR4RtbHdjyG00WYqgD5nF
{
    char_T f1[16];
};
#endif /* c1_struct_c1_tag_6jR4RtbHdjyG00WYqgD5nF */
#ifndef c1_typedef_c1_cell_wrap_2
#define c1_typedef_c1_cell_wrap_2
typedef struct c1_tag_6jR4RtbHdjyG00WYqgD5nF c1_cell_wrap_2;
#endif /* c1_typedef_c1_cell_wrap_2 */
#ifndef c1_struct_c1_tag_njgfiHhWBCqqqpWsKZxr7F
#define c1_struct_c1_tag_njgfiHhWBCqqqpWsKZxr7F
struct c1_tag_njgfiHhWBCqqqpWsKZxr7F
{
    char_T f1[15];
    char_T f2[15];
    char_T f3[12];
    char_T f4[11];
    char_T f5[16];
};
#endif /* c1_struct_c1_tag_njgfiHhWBCqqqpWsKZxr7F */
#ifndef c1_typedef_c1_cell_4
#define c1_typedef_c1_cell_4
typedef struct c1_tag_njgfiHhWBCqqqpWsKZxr7F c1_cell_4;
#endif /* c1_typedef_c1_cell_4 */
#ifndef c1_struct_c1_tag_w3m1Q26ivrDTAtgc0mcqVE
#define c1_struct_c1_tag_w3m1Q26ivrDTAtgc0mcqVE
struct c1_tag_w3m1Q26ivrDTAtgc0mcqVE
{
    c1_s_FDrX8kOEjZXLXru8nW4swE _data;
};
#endif /* c1_struct_c1_tag_w3m1Q26ivrDTAtgc0mcqVE */
#ifndef c1_typedef_c1_s_w3m1Q26ivrDTAtgc0mcqVE
#define c1_typedef_c1_s_w3m1Q26ivrDTAtgc0mcqVE
typedef struct c1_tag_w3m1Q26ivrDTAtgc0mcqVE c1_s_w3m1Q26ivrDTAtgc0mcqVE;
#endif /* c1_typedef_c1_s_w3m1Q26ivrDTAtgc0mcqVE */
#ifndef c1_struct_c1_tag_JkNjgv3CFjBZhduPupEzEE
#define c1_struct_c1_tag_JkNjgv3CFjBZhduPupEzEE
struct c1_tag_JkNjgv3CFjBZhduPupEzEE
{
    c1_cell_3 _data;
};
#endif /* c1_struct_c1_tag_JkNjgv3CFjBZhduPupEzEE */
#ifndef c1_typedef_c1_s_JkNjgv3CFjBZhduPupEzEE
#define c1_typedef_c1_s_JkNjgv3CFjBZhduPupEzEE
typedef struct c1_tag_JkNjgv3CFjBZhduPupEzEE c1_s_JkNjgv3CFjBZhduPupEzEE;
#endif /* c1_typedef_c1_s_JkNjgv3CFjBZhduPupEzEE */
#ifndef c1_struct_c1_tag_1nlLkVeIuST25DF6il3ApD
#define c1_struct_c1_tag_1nlLkVeIuST25DF6il3ApD
struct c1_tag_1nlLkVeIuST25DF6il3ApD
{
    c1_cell_wrap_2 _data;
};
#endif /* c1_struct_c1_tag_1nlLkVeIuST25DF6il3ApD */
#ifndef c1_typedef_c1_s_1nlLkVeIuST25DF6il3ApD
#define c1_typedef_c1_s_1nlLkVeIuST25DF6il3ApD
typedef struct c1_tag_1nlLkVeIuST25DF6il3ApD c1_s_1nlLkVeIuST25DF6il3ApD;
#endif /* c1_typedef_c1_s_1nlLkVeIuST25DF6il3ApD */
#ifndef c1_struct_c1_tag_uzuPWHtc1cM7ZRTfbsKeiF
#define c1_struct_c1_tag_uzuPWHtc1cM7ZRTfbsKeiF
struct c1_tag_uzuPWHtc1cM7ZRTfbsKeiF
{
    c1_cell_4 _data;
};
#endif /* c1_struct_c1_tag_uzuPWHtc1cM7ZRTfbsKeiF */
#ifndef c1_typedef_c1_s_uzuPWHtc1cM7ZRTfbsKeiF
#define c1_typedef_c1_s_uzuPWHtc1cM7ZRTfbsKeiF
typedef struct c1_tag_uzuPWHtc1cM7ZRTfbsKeiF c1_s_uzuPWHtc1cM7ZRTfbsKeiF;
#endif /* c1_typedef_c1_s_uzuPWHtc1cM7ZRTfbsKeiF */

/* Named Constants */
#define CALL_EVENT (-1)

/* Variable Declarations */

/* Variable Definitions */

/* Function Declarations */

/* Function Definitions */
void initialize_c1_ArmCalibV2(SimStruct *S, gvar_instance *ptr_gvar_instance)
{
    (void)ptr_gvar_instance;
    sim_mode_is_external(S);
    sf_get_time(S);
}

void initialize_params_c1_ArmCalibV2(SimStruct *S, gvar_instance *ptr_gvar_instance)
{
    (void)S;
    (void)ptr_gvar_instance;
}

void mdl_start_c1_ArmCalibV2(SimStruct *S, gvar_instance *ptr_gvar_instance)
{
    (void)ptr_gvar_instance;
    sim_mode_is_external(S);
}

void mdl_terminate_c1_ArmCalibV2(SimStruct *S, gvar_instance *ptr_gvar_instance)
{
    (void)S;
    (void)ptr_gvar_instance;
}

void mdl_setup_runtime_resources_c1_ArmCalibV2(SimStruct *S, gvar_instance *ptr_gvar_instance)
{
    sfSetAnimationVectors(S, &ptr_gvar_instance->c1_JITStateAnimation[0], &ptr_gvar_instance->c1_JITTransitionAnimation[0]);
}

void mdl_cleanup_runtime_resources_c1_ArmCalibV2(SimStruct *S, gvar_instance *ptr_gvar_instance)
{
    (void)S;
    (void)ptr_gvar_instance;
}

void enable_c1_ArmCalibV2(SimStruct *S, gvar_instance *ptr_gvar_instance)
{
    (void)ptr_gvar_instance;
    sf_get_time(S);
}

void disable_c1_ArmCalibV2(SimStruct *S, gvar_instance *ptr_gvar_instance)
{
    (void)ptr_gvar_instance;
    sf_get_time(S);
}

void sf_gateway_c1_ArmCalibV2(SimStruct *S, gvar_instance *ptr_gvar_instance)
{
    static char_T c1_b[30] = { 'C', 'o', 'd', 'e', 'r', ':', 't', 'o', 'o', 'l', 'b', 'o', 'x', ':', 'O', 'u', 't', 'O', 'f', 'T', 'a', 'r', 'g', 'e', 't', 'R', 'a', 'n', 'g', 'e' };
    emlrtStack c1_b_st;
    emlrtStack c1_c_st;
    emlrtStack c1_d_st;
    emlrtStack c1_st = { NULL,     /* site */
NULL,     /* tls */
NULL    /* prev */
 };
    const mxArray *c1_b_y = NULL;
    const mxArray *c1_c_y = NULL;
    const mxArray *c1_d_y = NULL;
    const mxArray *c1_y = NULL;
    real_T c1_x;
    int32_T c1_c;
    c1_st.tls = ptr_gvar_instance->c1_fEmlrtCtx;
    c1_b_st.prev = &c1_st;
    c1_b_st.tls = c1_st.tls;
    c1_c_st.prev = &c1_b_st;
    c1_c_st.tls = c1_b_st.tls;
    c1_d_st.prev = &c1_c_st;
    c1_d_st.tls = c1_c_st.tls;
    sf_get_time(S);
    ptr_gvar_instance->c1_JITTransitionAnimation[0] = 0U;
    c1_x = *ptr_gvar_instance->c1_u;
    for (c1_c = 0; c1_c < 3; c1_c++) {
        (*ptr_gvar_instance->c1_out)[c1_c] = rtNaN;
    }
    c1_b_st.site = &ptr_gvar_instance->c1_emlrtRSI;
    c1_c_st.site = &ptr_gvar_instance->c1_b_emlrtRSI;
    c1_d_st.site = &ptr_gvar_instance->c1_c_emlrtRSI;
    if ((c1_x >= 0.0) && (c1_x <= 255.0)) {
    } else {
        c1_y = NULL;
        sf_mex_assign(&c1_y, sf_mex_create("y", c1_b, 10, 0U, 1, 0U, 2, 1, 30), false);
        c1_b_y = NULL;
        sf_mex_assign(&c1_b_y, sf_mex_create("y", c1_b, 10, 0U, 1, 0U, 2, 1, 30), false);
        c1_x = 0.0;
        c1_c_y = NULL;
        sf_mex_assign(&c1_c_y, sf_mex_create("y", &c1_x, 0, 0U, 0, 0U, 0), false);
        c1_x = 255.0;
        c1_d_y = NULL;
        sf_mex_assign(&c1_d_y, sf_mex_create("y", &c1_x, 0, 0U, 0, 0U, 0), false);
        sf_mex_call(&c1_d_st, &ptr_gvar_instance->c1_emlrtMCI, "error", 0U, 2U, 14, c1_y, 14, sf_mex_call(&c1_d_st, NULL, "getString", 1U, 1U, 14, sf_mex_call(&c1_d_st, NULL, "message", 1U, 3U, 14, c1_b_y, 14, c1_c_y, 14, c1_d_y)));
    }
}

void ext_mode_exec_c1_ArmCalibV2(SimStruct *S, gvar_instance *ptr_gvar_instance)
{
    (void)S;
    (void)ptr_gvar_instance;
}

const mxArray *get_sim_state_c1_ArmCalibV2(SimStruct *S, gvar_instance *ptr_gvar_instance)
{
    const mxArray *c1_b_y = NULL;
    const mxArray *c1_st = NULL;
    const mxArray *c1_y = NULL;
    (void)S;
    c1_st = NULL;
    c1_y = NULL;
    sf_mex_assign(&c1_y, sf_mex_createcellmatrix(1, 1), false);
    c1_b_y = NULL;
    sf_mex_assign(&c1_b_y, sf_mex_create("y", *ptr_gvar_instance->c1_out, 0, 0U, 1, 0U, 2, 1, 3), false);
    sf_mex_setcell(c1_y, 0, c1_b_y);
    sf_mex_assign(&c1_st, c1_y, false);
    return c1_st;
}

void set_sim_state_c1_ArmCalibV2(SimStruct *S, gvar_instance *ptr_gvar_instance, const mxArray *c1_st)
{
    const mxArray *c1_b_u;
    real_T c1_b[3];
    int32_T c1_c;
    c1_b_u = sf_mex_dup(c1_st);
    c1_emlrt_marshallIn(S, ptr_gvar_instance, sf_mex_dup(sf_mex_getcell(c1_b_u, 0)), "out", c1_b);
    for (c1_c = 0; c1_c < 3; c1_c++) {
        (*ptr_gvar_instance->c1_out)[c1_c] = c1_b[c1_c];
    }
    sf_mex_destroy(&c1_b_u);
    sf_mex_destroy(&c1_st);
}

void c1_emlrt_marshallIn(SimStruct *S, gvar_instance *ptr_gvar_instance, const mxArray *c1_nullptr, const char_T *c1_identifier, real_T c1_y[3])
{
    emlrtMsgIdentifier c1_thisId;
    c1_thisId.fIdentifier = (const char_T *)c1_identifier;
    c1_thisId.fParent = NULL;
    c1_thisId.bParentIsCell = false;
    c1_b_emlrt_marshallIn(S, ptr_gvar_instance, sf_mex_dup(c1_nullptr), &c1_thisId, c1_y);
    sf_mex_destroy(&c1_nullptr);
}

void c1_b_emlrt_marshallIn(SimStruct *S, gvar_instance *ptr_gvar_instance, const mxArray *c1_b_u, const emlrtMsgIdentifier *c1_parentId, real_T c1_y[3])
{
    real_T c1_b[3];
    int32_T c1_c;
    (void)S;
    (void)ptr_gvar_instance;
    sf_mex_import(c1_parentId, sf_mex_dup(c1_b_u), c1_b, 1, 0, 0U, 1, 0U, 2, 1, 3);
    for (c1_c = 0; c1_c < 3; c1_c++) {
        c1_y[c1_c] = c1_b[c1_c];
    }
    sf_mex_destroy(&c1_b_u);
}

void init_dsm_address_info(SimStruct *S, gvar_instance *ptr_gvar_instance)
{
    (void)S;
    (void)ptr_gvar_instance;
}

void init_simulink_io_address(SimStruct *S, gvar_instance *ptr_gvar_instance)
{
    ptr_gvar_instance->c1_fEmlrtCtx = (void *)sfrtGetEmlrtCtx(S);
    ptr_gvar_instance->c1_u = (real_T *)ssGetInputPortSignal_wrapper(S, 0);
    ptr_gvar_instance->c1_out = (real_T (*)[3])ssGetOutputPortSignal_wrapper(S, 1);
}

void JIT_release_mem_fcn(gvar_instance *ptr_gvar_instance)
{
    free(ptr_gvar_instance);
}

gvar_instance *JIT_init_mem_fcn(void)
{
    gvar_instance *ptr_gvar_instance;
    ptr_gvar_instance = (gvar_instance *)calloc((size_t)1U, sizeof(gvar_instance));
    ptr_gvar_instance->c1_b_emlrtMCI.lineNo = 81;
    ptr_gvar_instance->c1_b_emlrtMCI.colNo = 13;
    ptr_gvar_instance->c1_b_emlrtMCI.fName = "reshapeSizeChecks";
    ptr_gvar_instance->c1_b_emlrtMCI.pName = "C:\\Program Files\\MATLAB\\R2025b\\toolbox\\eml\\eml\\+coder\\+internal\\reshapeSizeChecks.m";
    ptr_gvar_instance->c1_b_emlrtRSI.lineNo = 28;
    ptr_gvar_instance->c1_b_emlrtRSI.fcnName = "char";
    ptr_gvar_instance->c1_b_emlrtRSI.pathName = "C:\\Program Files\\MATLAB\\R2025b\\toolbox\\eml\\lib\\matlab\\strfun\\char.m";
    ptr_gvar_instance->c1_c_emlrtMCI.lineNo = 86;
    ptr_gvar_instance->c1_c_emlrtMCI.colNo = 23;
    ptr_gvar_instance->c1_c_emlrtMCI.fName = "reshapeSizeChecks";
    ptr_gvar_instance->c1_c_emlrtMCI.pName = "C:\\Program Files\\MATLAB\\R2025b\\toolbox\\eml\\eml\\+coder\\+internal\\reshapeSizeChecks.m";
    ptr_gvar_instance->c1_c_emlrtRSI.lineNo = 39;
    ptr_gvar_instance->c1_c_emlrtRSI.fcnName = "charCastCheck";
    ptr_gvar_instance->c1_c_emlrtRSI.pathName = "C:\\Program Files\\MATLAB\\R2025b\\toolbox\\eml\\eml\\+coder\\+internal\\charCastCheck.m";
    ptr_gvar_instance->c1_d_emlrtMCI.lineNo = 88;
    ptr_gvar_instance->c1_d_emlrtMCI.colNo = 23;
    ptr_gvar_instance->c1_d_emlrtMCI.fName = "reshapeSizeChecks";
    ptr_gvar_instance->c1_d_emlrtMCI.pName = "C:\\Program Files\\MATLAB\\R2025b\\toolbox\\eml\\eml\\+coder\\+internal\\reshapeSizeChecks.m";
    ptr_gvar_instance->c1_d_emlrtRSI.lineNo = 26;
    ptr_gvar_instance->c1_d_emlrtRSI.fcnName = "sscanf";
    ptr_gvar_instance->c1_d_emlrtRSI.pathName = "C:\\Program Files\\MATLAB\\R2025b\\toolbox\\eml\\lib\\matlab\\strfun\\sscanf.m";
    ptr_gvar_instance->c1_e_emlrtMCI.lineNo = 58;
    ptr_gvar_instance->c1_e_emlrtMCI.colNo = 23;
    ptr_gvar_instance->c1_e_emlrtMCI.fName = "assertValidSizeArg";
    ptr_gvar_instance->c1_e_emlrtMCI.pName = "C:\\Program Files\\MATLAB\\R2025b\\toolbox\\eml\\eml\\+coder\\+internal\\assertValidSizeArg.m";
    ptr_gvar_instance->c1_e_emlrtRSI.lineNo = 45;
    ptr_gvar_instance->c1_e_emlrtRSI.fcnName = "sscanf";
    ptr_gvar_instance->c1_e_emlrtRSI.pathName = "C:\\Program Files\\MATLAB\\R2025b\\toolbox\\eml\\lib\\matlab\\strfun\\sscanf.m";
    ptr_gvar_instance->c1_emlrtMCI.lineNo = 55;
    ptr_gvar_instance->c1_emlrtMCI.colNo = 5;
    ptr_gvar_instance->c1_emlrtMCI.fName = "charCastCheck";
    ptr_gvar_instance->c1_emlrtMCI.pName = "C:\\Program Files\\MATLAB\\R2025b\\toolbox\\eml\\eml\\+coder\\+internal\\charCastCheck.m";
    ptr_gvar_instance->c1_emlrtRSI.lineNo = 6;
    ptr_gvar_instance->c1_emlrtRSI.fcnName = "MATLAB Function1";
    ptr_gvar_instance->c1_emlrtRSI.pathName = "#ArmCalibV2:675";
    ptr_gvar_instance->c1_f_emlrtMCI.lineNo = 64;
    ptr_gvar_instance->c1_f_emlrtMCI.colNo = 15;
    ptr_gvar_instance->c1_f_emlrtMCI.fName = "assertValidSizeArg";
    ptr_gvar_instance->c1_f_emlrtMCI.pName = "C:\\Program Files\\MATLAB\\R2025b\\toolbox\\eml\\eml\\+coder\\+internal\\assertValidSizeArg.m";
    ptr_gvar_instance->c1_f_emlrtRSI.lineNo = 52;
    ptr_gvar_instance->c1_f_emlrtRSI.fcnName = "reshapeSizeChecks";
    ptr_gvar_instance->c1_f_emlrtRSI.pathName = "C:\\Program Files\\MATLAB\\R2025b\\toolbox\\eml\\eml\\+coder\\+internal\\reshapeSizeChecks.m";
    ptr_gvar_instance->c1_g_emlrtRSI.lineNo = 114;
    ptr_gvar_instance->c1_g_emlrtRSI.fcnName = "reshapeSizeChecks";
    ptr_gvar_instance->c1_g_emlrtRSI.pathName = "C:\\Program Files\\MATLAB\\R2025b\\toolbox\\eml\\eml\\+coder\\+internal\\reshapeSizeChecks.m";
    ptr_gvar_instance->c1_h_emlrtRSI.lineNo = 54;
    ptr_gvar_instance->c1_h_emlrtRSI.fcnName = "sscanf";
    ptr_gvar_instance->c1_h_emlrtRSI.pathName = "C:\\Program Files\\MATLAB\\R2025b\\toolbox\\eml\\lib\\matlab\\strfun\\sscanf.m";
    ptr_gvar_instance->c1_i_emlrtRSI.lineNo = 79;
    ptr_gvar_instance->c1_i_emlrtRSI.fcnName = "scanf";
    ptr_gvar_instance->c1_i_emlrtRSI.pathName = "C:\\Program Files\\MATLAB\\R2025b\\toolbox\\eml\\eml\\+coder\\+internal\\+io\\scanf.m";
    return ptr_gvar_instance;
}


