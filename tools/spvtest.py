"""Create a compute pipeline from a .spv on the real driver: python spvtest.py file.spv
Prints PIPELINE_OK or dies with the driver. Run in a subprocess for crash isolation."""
import struct, sys
from vulkan import *
from vulkan import ffi

d = open(sys.argv[1], 'rb').read()
w = struct.unpack('<%dI' % (len(d) // 4), d)
i = 5; types = {}; ptr = {}; var = {}; bind = {}; dset = {}
while i < len(w):
    wc, op = w[i] >> 16, w[i] & 0xffff; a = w[i + 1:i + wc]
    if op == 71:  # OpDecorate
        if a[1] == 33: bind[a[0]] = a[2]
        if a[1] == 34: dset[a[0]] = a[2]
    elif op == 25: types[a[0]] = ('image', a[6])       # sampled operand
    elif op == 26: types[a[0]] = ('sampler',)
    elif op == 27: types[a[0]] = ('sampledimage',)
    elif op in (28, 29): types[a[0]] = ('array', a[1])
    elif op == 30: types[a[0]] = ('struct',)
    elif op == 32: ptr[a[0]] = (a[1], a[2])
    elif op == 59: var[a[1]] = (a[0], a[2])
    i += wc
bindings = {}
for v, (pt, sc) in var.items():
    if v not in bind: continue
    t = types.get(ptr[pt][1], ('?',))
    while t[0] == 'array': t = types.get(t[1], ('?',))
    if sc == 12: k = VK_DESCRIPTOR_TYPE_STORAGE_BUFFER
    elif sc == 2: k = VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER
    elif t[0] == 'sampler': k = VK_DESCRIPTOR_TYPE_SAMPLER
    elif t[0] == 'sampledimage': k = VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER
    elif t[0] == 'image': k = VK_DESCRIPTOR_TYPE_STORAGE_IMAGE if t[1] == 2 else VK_DESCRIPTOR_TYPE_SAMPLED_IMAGE
    else: continue
    bindings[bind[v]] = k   # aliased buffer views share one binding

inst = vkCreateInstance(VkInstanceCreateInfo(pApplicationInfo=VkApplicationInfo(apiVersion=VK_MAKE_VERSION(1, 3, 0))), None)
pd = [p for p in vkEnumeratePhysicalDevices(inst)
      if vkGetPhysicalDeviceProperties(p).deviceType == VK_PHYSICAL_DEVICE_TYPE_DISCRETE_GPU][0]
have = {e.extensionName for e in vkEnumerateDeviceExtensionProperties(pd, None)}
want = [e for e in ('VK_KHR_workgroup_memory_explicit_layout', 'VK_KHR_shader_maximal_reconvergence',
                    'VK_AMD_shader_image_load_store_lod', 'VK_EXT_shader_stencil_export') if e in have]
wg = ffi.new('VkPhysicalDeviceWorkgroupMemoryExplicitLayoutFeaturesKHR*')
wg.sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_WORKGROUP_MEMORY_EXPLICIT_LAYOUT_FEATURES_KHR
# The binding predates this extension: same shape as any one-bool feature struct.
mr = ffi.new('VkPhysicalDeviceShaderDemoteToHelperInvocationFeaturesEXT*')
mr.sType = 1000434000
mr.pNext = wg
f13 = ffi.new('VkPhysicalDeviceVulkan13Features*'); f13.sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VULKAN_1_3_FEATURES; f13.pNext = mr
f12 = ffi.new('VkPhysicalDeviceVulkan12Features*'); f12.sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VULKAN_1_2_FEATURES; f12.pNext = f13
f11 = ffi.new('VkPhysicalDeviceVulkan11Features*'); f11.sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VULKAN_1_1_FEATURES; f11.pNext = f12
f2 = ffi.new('VkPhysicalDeviceFeatures2*'); f2.sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_FEATURES_2; f2.pNext = f11
vkGetPhysicalDeviceFeatures2(pd, f2)
dev = vkCreateDevice(pd, VkDeviceCreateInfo(pNext=f2, pQueueCreateInfos=[VkDeviceQueueCreateInfo(
    queueFamilyIndex=0, queueCount=1, pQueuePriorities=[1.0])], ppEnabledExtensionNames=want), None)
dsl = vkCreateDescriptorSetLayout(dev, VkDescriptorSetLayoutCreateInfo(pBindings=[VkDescriptorSetLayoutBinding(
    binding=b, descriptorType=k, descriptorCount=1, stageFlags=VK_SHADER_STAGE_COMPUTE_BIT)
    for b, k in sorted(bindings.items())]), None)
pl = vkCreatePipelineLayout(dev, VkPipelineLayoutCreateInfo(pSetLayouts=[dsl], pPushConstantRanges=[
    VkPushConstantRange(stageFlags=VK_SHADER_STAGE_COMPUTE_BIT, offset=0, size=128)]), None)
mod = vkCreateShaderModule(dev, VkShaderModuleCreateInfo(codeSize=len(d), pCode=d), None)
print('MODULE_OK', len(bindings), 'bindings', flush=True)
vkCreateComputePipelines(dev, None, 1, [VkComputePipelineCreateInfo(layout=pl, stage=VkPipelineShaderStageCreateInfo(
    stage=VK_SHADER_STAGE_COMPUTE_BIT, module=mod, pName='main'))], None)
print('PIPELINE_OK', flush=True)
