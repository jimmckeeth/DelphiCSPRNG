unit Holon.ValidateRNG.Tests;

{
  Every "NIST worked example" test below reproduces a specific numerical example
  from NIST SP 800-22 Rev 1a's own text (section numbers given in each test's
  comment), extracted from the source PDF and cross-checked, not transcribed from
  memory - see docs/rng-validate-plan.md for how. The Binary Matrix Rank example
  uses the first 100,000 bits of the binary expansion of e, the same reference
  data NIST's own example (section 2.5.8) uses, sourced from the official NIST
  STS reference data files (data.e) and independently confirmed to start with
  the correct bits of e (10.10110111111000010101...) before use.
}

interface

uses
  SysUtils,
  DUnitX.TestFramework,
  Holon.CSRNG,
  Holon.CSRNG.Interfaces,
  Holon.ValidateRNG;

type
  [TestFixture]
  TValidateRNGTests = class
  private
    function BitStringToBytes(const S: string): TBytes;
    function HexToBytes(const Hex: string): TBytes;
    function NistExampleSequence: TBytes; // the shared 100-bit example used by 5 of the 7 tests
  public
    [Test]
    procedure TestErfc_KnownConstants;
    [Test]
    procedure TestPhi_KnownConstants;
    [Test]
    procedure TestIgamc_KnownConstants;

    [Test]
    procedure TestFrequency_NistWorkedExample;
    [Test]
    procedure TestBlockFrequency_NistWorkedExample;
    [Test]
    procedure TestRuns_NistWorkedExample;
    [Test]
    procedure TestLongestRunOfOnes_NistWorkedExample;
    [Test]
    procedure TestApproximateEntropy_NistWorkedExample;
    [Test]
    procedure TestCumulativeSums_Forward_NistWorkedExample;
    [Test]
    procedure TestCumulativeSums_Reverse_NistWorkedExample;
    [Test]
    procedure TestBinaryMatrixRank_NistWorkedExample;

    [Test]
    procedure TestFrequency_AllZeros_FailsDecisively;
    [Test]
    procedure TestFrequency_AllOnes_FailsDecisively;
    [Test]
    procedure TestRuns_Alternating_FailsDecisively;
    [Test]
    procedure TestFrequency_Alternating_Passes;

    [Test]
    procedure TestFrequency_TooShort_Raises;
    [Test]
    procedure TestBinaryMatrixRank_TooShort_Raises;
    [Test]
    procedure TestLongestRunOfOnes_OutOfSupportedRange_Raises;
    [Test]
    procedure TestApproximateEntropy_MZero_Raises;

    [Test]
    procedure TestRunSuite_LiveCSRNG_AllResultsSane;
    [Test]
    procedure TestRunSuite_ProviderOverload_Works;
  end;

implementation

const
  // Section 2.1.8 / 2.2.8 / 2.3.8 / 2.12.8 / 2.13.8: the same 100-bit example
  // sequence is reused across Frequency, Block Frequency, Runs, Approximate
  // Entropy, and Cumulative Sums.
  NistSeq100 =
    '11001001000011111101101010100010001000010110100011' +
    '00001000110100110001001100011001100010100010111000';

  // Section 2.4.8: a separate 128-bit example, specific to the Longest Run test.
  NistSeq128 =
    '1100110000010101011011000100110011100000000000100100110101010001000100111101011010000000110101111100' +
    '1100111001101101100010110010';

{ TValidateRNGTests }

function TValidateRNGTests.BitStringToBytes(const S: string): TBytes;
var
  ByteCount, I, BitIdx: Integer;
begin
  ByteCount := (Length(S) + 7) div 8;
  SetLength(Result, ByteCount);
  FillChar(Result[0], ByteCount, 0);
  for I := 1 to Length(S) do
  begin
    if S[I] = '1' then
    begin
      BitIdx := I - 1;
      Result[BitIdx shr 3] := Result[BitIdx shr 3] or (1 shl (7 - (BitIdx and 7)));
    end;
  end;
end;

function TValidateRNGTests.HexToBytes(const Hex: string): TBytes;
var
  I: Integer;
begin
  SetLength(Result, Length(Hex) div 2);
  for I := 0 to High(Result) do
    Result[I] := Byte(StrToInt('$' + Copy(Hex, I * 2 + 1, 2)));
end;

function TValidateRNGTests.NistExampleSequence: TBytes;
begin
  Result := BitStringToBytes(NistSeq100);
end;

{ Special-function accuracy, independent of any NIST-specific text }

procedure TValidateRNGTests.TestErfc_KnownConstants;
begin
  Assert.AreEqual(1.0, Erfc(0), 1E-9);
  Assert.AreEqual(0.15729920705028513, Erfc(1), 1E-9);
  Assert.AreEqual(2.0, Erfc(-1E10), 1E-9); // erfc(-infinity) -> 2
  Assert.IsTrue(Erfc(1E10) < 1E-9); // erfc(+infinity) -> 0
end;

procedure TValidateRNGTests.TestPhi_KnownConstants;
begin
  Assert.AreEqual(0.5, Phi(0), 1E-9);
  Assert.AreEqual(0.8413447460685429, Phi(1), 1E-6); // standard normal CDF at 1
end;

procedure TValidateRNGTests.TestIgamc_KnownConstants;
begin
  Assert.AreEqual(1.0, Igamc(1, 0), 1E-9);
  Assert.AreEqual(Exp(-1), Igamc(1, 1), 1E-9); // Igamc(1, x) = e^-x, a closed-form identity
  Assert.AreEqual(Exp(-2), Igamc(1, 2), 1E-9);
end;

{ NIST worked examples }

// Section 2.1.8: n=100, S=-16, s_obs=1.6, P-value=0.109599
procedure TValidateRNGTests.TestFrequency_NistWorkedExample;
var
  R: TRandomnessTestResult;
begin
  R := TRandomnessTests.Frequency(NistExampleSequence, 100);
  Assert.AreEqual(0.109599, R.PValue, 1E-5);
  Assert.IsTrue(R.Passed);
end;

// Section 2.2.8: n=100, M=10, N=10, chi2=7.2, P-value=0.706438
procedure TValidateRNGTests.TestBlockFrequency_NistWorkedExample;
var
  R: TRandomnessTestResult;
begin
  R := TRandomnessTests.BlockFrequency(NistExampleSequence, 100, 10);
  Assert.AreEqual(0.706438, R.PValue, 1E-5);
  Assert.IsTrue(R.Passed);
end;

// Section 2.3.8: n=100, pi=0.42, V_n(obs)=52, P-value=0.500798
procedure TValidateRNGTests.TestRuns_NistWorkedExample;
var
  R: TRandomnessTestResult;
begin
  R := TRandomnessTests.Runs(NistExampleSequence, 100);
  Assert.AreEqual(0.500798, R.PValue, 1E-5);
  Assert.IsTrue(R.Passed);
end;

// Section 2.4.8: n=128, M=8, K=3, chi2=4.882457, P-value=0.180609
procedure TValidateRNGTests.TestLongestRunOfOnes_NistWorkedExample;
var
  R: TRandomnessTestResult;
begin
  R := TRandomnessTests.LongestRunOfOnes(BitStringToBytes(NistSeq128), 128);
  Assert.AreEqual(0.180609, R.PValue, 1E-5, R.Detail);
  Assert.IsTrue(R.Passed);
end;

// Section 2.12.8: n=100, m=2, ApEn=0.665393, chi2=5.550792, P-value=0.235301
procedure TValidateRNGTests.TestApproximateEntropy_NistWorkedExample;
var
  R: TRandomnessTestResult;
begin
  R := TRandomnessTests.ApproximateEntropy(NistExampleSequence, 100, 2);
  Assert.AreEqual(0.235301, R.PValue, 1E-5, R.Detail);
  Assert.IsTrue(R.Passed);
end;

// Section 2.13.8: n=100, forward z=1.6, P-value=0.219194
procedure TValidateRNGTests.TestCumulativeSums_Forward_NistWorkedExample;
var
  R: TRandomnessTestResult;
begin
  R := TRandomnessTests.CumulativeSums(NistExampleSequence, 100, cmForward);
  Assert.AreEqual(0.219194, R.PValue, 1E-5);
  Assert.IsTrue(R.Passed);
end;

// Section 2.13.8: n=100, reverse z=1.9, P-value=0.114866
procedure TValidateRNGTests.TestCumulativeSums_Reverse_NistWorkedExample;
var
  R: TRandomnessTestResult;
begin
  R := TRandomnessTests.CumulativeSums(NistExampleSequence, 100, cmReverse);
  Assert.AreEqual(0.114866, R.PValue, 1E-5);
  Assert.IsTrue(R.Passed);
end;

// Section 2.5.8: first 100,000 bits of e, M=Q=32, N=97, F_M=23, F_(M-1)=60,
// chi2=1.2619656, P-value=0.532069.
procedure TValidateRNGTests.TestBinaryMatrixRank_NistWorkedExample;
const
  // First 100,000 bits of the binary expansion of e, packed as hex (12,500
  // bytes). Sourced from NIST's own STS reference data file (data.e) - the
  // same data NIST's own worked example in section 2.5.8 uses. Independently
  // confirmed before use to start with the correct binary digits of
  // e = 10.1011011111100001010100...
  DataEHex =
    'adf85458a2bb4a9aafdc5620273d3cf1d8b9c583ce2d3695a9e13641146433fbcc939dce249b3ef97d2fe363630c75d8f681b202aec4617ad3df1ed5d5fd65612433f51f5f066ed0856365553ded1af3' +
    'b557135e7f57c935984f0c70e0e68b77e2a689daf3efe8721df158a136ade73530acca4f483a797abc0ab182b324fb61d108a94bb2c8e3fbb96adab760d7f4681d4f42a3de394df4ae56ede76372bb19' +
    '0b07a7c8ee0a6d709e02fce1cdf7e2ecc03404cd28342f619172fe9ce98583ff8e4f1232eef28183c3fe3b1b4c6fad733bb5fcbc2ec22005c58ef1837d1683b2c6f34a26c1b2effa886b4238611fcfdc' +
    'de355b3b6519035bbc34f4def99c023861b46fc9d6e6c9077ad91d2691f7f7ee598cb0fac186d91caefe130985139270b4130c93bc437944f4fd4452e2d74dd364f2e21e71f54bff5cae82ab9c9df69e' +
    'e86d2bc522363a0dabc521979b0deada1dbf9a42d5c4484e0abcd06bfa53ddef3c1b20ee3fd59d7c25e41d2b669e1ef16e6f52c3164df4fb7930e9e4e58857b6ac7d5f42d69f6d187763cf1d55034004' +
    '87f55ba57e31cc7a7135c886efb4318aed6a1e012d9e6832a907600a918130c46dc778f971ad0038092999a333cb8b7a1a1db93d7140003c2a4ecea9f98d0acc0a8291cdcec97dcf8ec9b55a7f88a46b' +
    '4db5a851f44182e1c68a007e5e0dd9020bfd64b645036c7a4e677d2c38532a3a23ba4442caf53ea63bb454329b7624c8917bdd64b1c0fd4cb38e8c334c701c3acdad0657fccfec719b1f5c3e4e46041f' +
    '388147fb4cfdb477a52471f7a9a96910b855322edb6340d8a00ef092350511e30abec1fff9e3a26e7fb29f8c183023c3587e38da0077d9b4763e4e4b94b2bbc194c6651e77caf992eeaac0232a281bf6' +
    'b3a739c1226116820ae8db5847a67cbef9c9091b462d538cd72b03746ae77f5e62292c311562a846505dc82db854338ae49f5235c95b91178ccf2dd5cacef403ec9d1810c6272b045b3b71f9dc6b80d6' +
    '3fdd4a8e9adb1e6962a69526d43161c1a41d570d7938dad4a40e329ccff46aaa36ad004cf600c8381e425a31d951ae64fdb23fcec9509d43687feb69edd1cc5e0b8cc3bdf64b10ef86b63142a3ab8829' +
    '555b2f747c932665cb2c0f1cc01bd70229388839d2af05e454504ac78b7582822846c0ba35c35f5c59160cc046fd8251541fc68c9c86b022bb7099876a460e7451a8a93109703fee1c217e6c3826e52c' +
    '51aa691e0e423cfc99e9e31650c1217b624816cdad9a95f9d5b8019488d9c0a0a1fe3075a577e23183f81d4a3f2fa4571efc8ce0ba8a4fe8b6855dfe72b0a66eded2fbabfbe58a30fafabe1c5d71a87e' +
    '2f741ef8c1fe86fea6bbfde530677f0d97d11d49f7a8443d0822e506a9f4614e011e2a94838ff88cd68c8bb7c51eef6d49ea8ab4f2c3df5bb4e0735ab0d687492fe26dd4065816bba77eae973f3b40ce' +
    'e8840a82f6f8ed275c9cbe2782740239756f6648e4d8a187ad098a5f16104e5d4551cf3ca8f5b796312ec6e46b65eafc0a3a5997693b3a037704f837d0c8bb683f4e26c5d7a3443423148c29ad5db253' +
    'f14ad39d2cb8d083a40b20bb9ebae0170badd945faaffee1ddcde30e01b24741fc42759d49f0615a0d1205535a485841d56fbcc2e009f97a2c13964ba2cba8d528987aaed214591cb51a699a093c9351' +
    '2c573850bf2d94c1fc8736aef5a16331eb8f3b81ab992fb6468104b9bccee813ead5ee39485972a07431f4460e175b48c291f87a2d4ebc3669eab0949ed1b1009e106a8e169031b145ebe3b49a3d1a66' +
    '435b6b8ada3d8bf76dbcc0e9d662fa356dc68ea00dc4b1f9aec6f2f0321efa96a3b8fa387a39baea67011f6d7db84dc9e5b7098d395954b60317eebe09aa70f70b067a65a789d96fe207baa2fd9c1407' +
    'da8e7325794d6445fe7fb02b7edee5654a6f4b1ef976d95c1f132937a1a424bc00a7678d491bd254e9f81d7946021a3e96f5828ca2cffa94c21345d3277a323da865f598d66da688a4b497c4bc6cc88e' +
    '4ac40d6a0562843e5583fc649f89a6fca9b859129590f29c2cbd9878a8f284d39457a0718b44a6e8edb59b38eeb6550db057f39bb3354aab49c411f7bd56c210cd5247e19664311c599846bb773712e0' +
    '1e846f8213616c3bea02f4c7c2808791600960b47d816c6b8f8c9d2b9094d7689d3dffb5f168e1a7336f2963153749261a964fc62ee3108a479e593264f4532eb0d8ea00688123538f1be3b3e9d7f334' +
    '0269926bd7b083135fb5e10ded1adaabd6e76d2b7d00b3d9014c0463a614af9080fc8b2eda37fcafce29bab82db439eeff9374e5f509007d85066c7ce300e2f492eb4bcc1c70b8511c87fdca1994c386' +
    'f1fdb727d885f89616b0ffdf23ec7a1a08cf58b7a179b7dceff472079159b3a58d65408b0ee441590bc1ca50e5106f3660fa97c6386f3353b315b2ad0e437d8556c86f62adf1cbc00d886d34600deb39' +
    '11bb0483948534618bac171aed5f7b5e26c766068c6e5a8cecd4839d9917739b150782656dec56b600231f5ae724257c158fbbfec0779b13ff6a36f590ff40ffd7171742bed1f8ced07326c0536d49b2' +
    'b93f55057d5cb13a4604c9d292a14387d8cd0e30541968c453fb7373cacd93a070562b58063089859481df88312c5a9781eb1e44a5f6875fc8ae4edeef57c12f24a9d6176b49cf13379ef1ed9ecca8e0' +
    '829e71e1d74515171b447d2c2cd1beb7a3ba7b3427a383786fdc2786132a424dc06213dd9f1c859ffa43f1c1e10e706f95e52ef310936eab07d340fb06cdf1f44db1269db016bbbb5cef91ec21c39694' +
    '44574d31772dd2a04077cad6abfe6783c1cfafd8c768a796c7dd2215f069f07fab98853e7ade65483a3c502db12708c419d049eda2477953f439179a50589600f449b0e543036fdcad8a6a74a9bbb3d3' +
    '013d37aeb213fee14ee06006cf676f464700123cf04306df00d7de793589c4aa667171a9b3d1f570e02ec77d493679dff1eef7fb8f8f9dead7917d8cb17ee84ef55ecf319c3f7e82c2fd92a58124abaa' +
    '852ec55ff522648da327f428bafe51382ce585372fd14ebe5d73acf6941f2ed020c2081d724019cbbc852c1719d1c38e3ecc5dab86697057ee9bce15a4ea8121365cc793492dd181a4b03a1060e8d1c8' +
    '6c5f163ce06737ec78023abf3b57e754edde369c5850e2977612cd83c1bc3050aa742b9fc546a2775dc1894617d6724dd6361ca80eb5a5b8234bf8c3406218746b2732299c265cc92412f221cc8eea57' +
    '237412e6f8c49da68c79c7a6228cef4723bc0928e60fa1177bf2bc00e9a223778988e117d61afd37223d045d5fa1ca0315076034403ad11b0dbef532a8377bda32bbaaecc8a19615f676973620332912' +
    '1e290b2e7947c67f5542ea8a598c407ca7449132fedb32007cfbd59b90fe31adbfd7d930fa530edd67c0945897bc1be2bfc0120ddef318e0cb3e333a9d05602415cee22552672c29b5331a11d6dc441d' +
    '2957f4d89281ad0eaab7313cdaad090b337bcdbf91f315a093a72ca0c7b878f258e2e37fecde83f4a6134b8b0cf4de2a6703f43efced910c6b75556f9b8a47e6fdd4e840d5581dbd9b2e870ef371598b' +
    'd8e7089f52b4f9744715586c2ac099120666423f1980a0a7662e0961ac11e40fd92566dfab4d265502d2d9c731b753bebb923a9758adac286d65545071d57c681181350cac9e66d3bd1ba114b62211a4' +
    '891105bedb4c6a10eb37d33de87b703d4b72e3867fcb23e4b900e5d97a4a7e1563f553ba34544f57a9fb07dfa04adfdcce1e81dd3142f4f3b771444dc2860e06ba19fe12dbce5bba9459152bafb92ec0' +
    '34bf04431126e264758eb6b7a552017c227c4bac51df5496e0dcecd0d30fad5ade8bc463f73300521036fb90efb26a28d1d1f7ae80277a4b55a700b35cb18b9c4d4f92a4263d1ceb890ca52efc66d4a1' +
    '653ee731eaef926b34efa08fe0cbabe3cf990475fb60e63f39e39807a1b3cca2629e5751efc4c52087e281d588425e26bf08c5f8f78a4b3ae3e9ee2a13599cf63d42fdcc901a9ef14ee765463d0ed1fb' +
    'a1228f732b63c820f2985864359693ca983d4f038ea5bb98d2cd787cb3e99613b115afa806d03bccc422a37e23667921d312260aba0e965198c68220a0848c9eaa92b0606de577a47f99fcbefb7b5145' +
    '767ab42fcf7b0a33079bab183c9b33030541b184d97e3cc0c968d8b774ad15401c2de8eec9cb2d6d1a73f8ea08a70cd35a9b35c08d0acdebb5f81c3d484e1bd1bb013e99690ddadb3649dbaf375d250b' +
    'e2dcea1c7f4044d9528c7ee30d9bcadf1dd02051f7a10ee5d84143409c88bdeb00a85db45b1fe0fb401ab4eb6eea21ee6c1bdd8b6c8065bec9d8e5f881ffe8ded196fba910e9a84358a2a433a33b62b1' +
    '976ef5d42b19027d3c314f8510e3a8e79c475232ccc1c87203c0f4575f5118dcf6b533cfe485c463552696179146ce7139061377a17f1baf817ab2039f8d239502a0511a391c3c50f8b317eb7c9f3cb7' +
    '7e7a0609203b9427d5a04ee07516460434d137984354c12e123bc9d6cee385878504e2ce8bdc96450ceb13d05d5851d34ffdca118edd0b6e8dc6b2eca4ac09d6b56fe2083064a101199df66a9a7be9e6' +
    'd24093992f60fa241f3f0f912c3447dd32fa67e69249fcfbbde224afcbdd5d2c2b00bee8b9f8ab62638567f865423f3fc77a2c27cf395736b9192ccfaaa87c3a4d7b43148c6f8dd80c0f6072c16a7c8b' +
    'a0f7587105c118bd88dd3f27af2bb8ef34524b8ad757991cff0520412182e1db5a1409b54f51c50631b250b9232a238aeb6f14be8affcb9c2d4feaef39266eb1f62631d0e603af5b4f15398a0936d262' +
    '92956ef0f855a3acc63ab34fe5ee37f3cc51ad04d78d54407b250bc879ebec45c9807ab2f5d604b6908a85e4a8e913609b3aa73880b1aa6fc74b6760e2b538abae188d265dc726a84838d99fc9a45c84' +
    'b06e13c21d96cb2af2aa263d78cd8d22bd7528d3f557dc6a2686cac254aef22c747be1a858d2afca8f0ea49ee0c77937bc31422de25528f11b06d529118f0c049e74ac3992c5e3aa6a73e955f30e72a4' +
    'f8ffbf3f8196fbf5432928af4e6d46cab0459849281c63c326337d789e27106e88fb857e630455ffb4589fa6842310e96ba2fed2f4778ffd5f8dc50e51abb62ee5a46c439d5ee9d40be397acdc2e3ba6' +
    '4bab075a5555047342ee18ad641aa3c2bb148d8ea037c0620c1d0bf169c6e7a549c6cecad4ca16f626da5c1b72d28622f611136998d60ff6e13865e3d17cbd819c1dab79e3baa0265bfc4252aa70fd81' +
    '9857b38a99299347e41df5f3cdd5566502c0f60a2c0cdfee73a0b2f2332f4559672966516c10ceb3270c7306818938d6c2daeddd5f2012e7e94a4b45218a762e2eaa31166abf1a214fc4a2eeb8464478' +
    '2319410dfafa983b349daa9d3996574f28d87f900945903f1fa0d32a17cb47e5183ab7e39fa4adc396ea3b83d26ef959abee080a5c3fa124b4aa466ae2d5d8a59acc20106972933cf6e3d8eefcb600f8' +
    'e220a292094e78730cafc9865332388f98a42f36b155ccc91a7085c5a7adf8f5711c1e684b678f1d07fffe993c8bfd826df2508a9ffba35437539828c0499ef31e06086351cd7a163ff518e4a93c139b' +
    '795b61e688f14937bc3ee2ffb4e19b7f72cd9cebfe1589ec0d615b7e3c703513921f038f2a98fa62456572bb18317e44d53a9d89c32af10ffbdbf517692db1dac68877b3e6475ba344c1622f8af2999e' +
    '29f0ea52ce170784b647b903be377b6698c4b9219400b8c8f6707741b20b1d67a061d5486b06b960314f06a17b91254205e160f531aef58f7ea857a6b7d4ab99abe9b7bd766b3d03686103091f5b0efa' +
    'dee290175cd97b4a57755d82b31ee7462cb5a84279ae156187ac367e4dba0a42ab28988bcd4c3aff9b9cb1edcde95805dfdc1a8389c190a79e9d1c10e7086a9e06f92f35d462f20dc6dba634e4176d0d' +
    'f110ae2699b9bbd796feaad0d3a5a0732516e8af4002b50df0151f93d0f0521913a7b16a9eea2db34a0fcc0e239460b78a3b1084266596fc138a9085f692eb1be4adb2d598a3c8d018d481c96395edf7' +
    'f986be5a063e754ba92bb6ca7a79c41d7ff309fd0b49c14a407005b97fe227475d41764939349f9e2cc1f76d18fcc20d51f689d996eae80be2b1c1ea31e6a533a92ef890b125ffa8444bcc9c2a2f2dce' +
    '111426ed702b824521a75c67f7bff708ff501e61cb2e9682c6ddb64eaa3cfdc9fb6e66ebbfa2ab9ff4547d3d5b3378ea9d451ee57bf1adcaa1de2b74bff3fc226ed1c14088eba01a711e493724e9890b' +
    '94996963ca16ff776c13483e4009785fab70dd46a0a54b6bc8f99b0d64d8df1be60c97886faae423374e63ee9f93ff7b9de300ad1810a539d88783f90b98f791e2e93aa5fa84726d6b35836c345ccb5f' +
    '8cdfb03d3152368744e9264ab92bce4c11ff5631e8535fa3a52cbc721bbfb0d7a9d1c35881c406fe3b382a55f8a28531e7fe69a0cd057a944e6203439247602516cb53a51a7e8fa5d9fe550cd3bbe3c9' +
    '56ffbede8ed1c00052fdea842c114ac551588673009c5a79b269014fd6d45cea064edeeba7c4966a73dddc5f5d07213b4015971ab6ac67a6ec43626670f2e0b72947a304f39c85fc03cc0a43e0ac39c4' +
    'ab775bf5c0999c8309f8619d1b6ea86e2b05616a264b8cc88096b3ac9e8ab7b5720ab545b16382a8e7f375168a8cd3ac134ad3916dabc8ee07532ede777e388494ef3193f9f1ba69ef83622501fa8cd2' +
    'd505fff4ec70adb1c175dad165e5090ff8a8cdea1b1f757f285ada876278574136c9f9d0202855c1a43b65798f3b180d603b5cb395be8a92d820e8975d5f74da4fcd60ada84f70f750cc4343797f5290' +
    '67293809d717db98f4a96dd64c443f6253b7e3503528fe1524dc0b9fc0f7738c11c5c128bf906475277512211e53f07a079220e280ddfb33631b6743935f4454b18fc102344ceda644deac4fffd2f676' +
    'b6614417d8c61bfc8f5f9829e6601f274096002c39ea07228c072a8dbc26bbe6a79039df053a3b7da2ccd56ec7e73cbf8d696208b15b775c489f3d773bba152a1a4655d9e155ce589e25a5059a48c0b3' +
    '6a01150ca17ee13f5e53927292eac1afe41bf3c0a626975b86bfdfda0e8658cc28829c3da9c8d24ef00a13c64fc64f16cbe93d413436a5731a4efb6db4b2f6cbc918e64049fdff3cf4016ae8f29e49fe' +
    '506c140ce14ae3f13a38930c86c9ab8d1d71a19fb85b15b667b48399e8220438227105a30f2cbdfa05aaec49f319044d35931d120029a35ebb72228a377cf0734f594d756abc1e24d3ae2b17e8abdb89' +
    '9893e4ade410d0b2d87502ad7071ca59c796fbbe6b5f9d61a2d5535062b410f72c88b3478d8a89f58ecafd16784ddd8f56f7bf179ebb499e358f2eb348691ba8a7d43a5778807625a88a54741f424d45' +
    'de10a21dd084b1a1dd67ade576afe0b38f5f157b4e2cf0cdbbaa7dc62d859a82c8d32c0ecab7678b5a4ffe5df6f74c760fea5eeb71c2f3c4353bd2c5a1d391104543358c0ab565780980ea7ac9eea160' +
    'bdb2fde9b418ce5e06cf23624913c3bbe3bddfbc9fe732c146277d4484dfa8f4fc8128088f1946701fa15d53fb5751e42e67f04d9f78029618a05d77f75e14fa0c91df8c4e773171fcaa74159121ad8f' +
    'df6efd88092b1cc1f91942a82c0043bce02782d54e9cec719f0f25f550314c15a2aa479f4dbdfe67cbd75e1f01eb7bd8b4e39c5a471fa19fae981f314d590b9c76bf78ceb96007a443027250c3345452' +
    'b1be2b2c7a5e59bb97df13db1de9d4fcbd92c5544050387ec7fd0a0ebd1ae1ccbe7d15d0edd951b03c1ebb45836aea48fa8c50f5b3be49f103153afe645f114959589cda65f368e5bced7d266efe51bf' +
    'bdd5bf67ccd5a5ff2e00ad9e6cb2003200606b551d43d3705a662afb0bd9e58b2c31f095d0333585c6da66c335294a89d6b833c665f624adc5685ce9ee32ae5ade79246c29628398c88b00b408fd3a63' +
    '8aef0ef6b26996f91a6c9fe9d5cde9dcd13c110b8857b1d7ec821d47efba0ca69febc62cc16083c67f60f33ff86d3e695c63b5969e25cf102eda8bc49b7ab83d9826e5f713ec205458d5a9b85940d27c' +
    '871956d76f384d2229366bc0b41688b4c32978deca6e588cd0fc7d0a682ffa63064cba24ae76bdefb8be601920796f60957e20350113583025853b79b03be47575a4976257c60a260251ffa66e02651e' +
    '7dbdc2cba11abcf35a8cf1ef6c02d7db961db94218cf7a3b454e40eec80cce7b8c9ee568f1f807a750d48657931c854d3d6cc1d60118268497db7b25eb2295771c88abc65656a3082e86856e57c7dd46' +
    '0bee930088fe3720061f7c32c2fe03ab11fefe9ba6735ab1b84a2c5bbdfd1c557d492058d5d74503c4eb33de79521b9dd361371a5a34eefb5edf68b4650bd3dd927ba5abc30e9ae31d28d81725342c90' +
    '0b23564c3f61efdf2c6b858b5f74aa91e4f030c4769758508d87d4e7c4225586fed1cfc33c1ad352cb785d1051167731c3f490ce2f3d6f144a608eab978cc901b45cf37be0e2dece23d0fc85ee57ace6' +
    '7af5d70104019143931bf3cbe00ce86855dd104ff178512c1cd63b8dc9ca8ec80b77500c66afd422ee47ef51eff1b89ec92f93c6d6786f568aa34023ee7f741a31590f15ff91e3d5d1cfd3c59933f618' +
    '55223fd736678f4299a7a8fc866a3f9a380649025d4f6d7e72cda5091c34d62666d4cc6f29a6661814fd22e0542fd33121d59ff880908af9562cb55ad773ee8207efa26796b9eac9007673899d54a4d5' +
    '0a0557d94b5621874c8e67cf0b2ea7e50b481cbfb8ecd6c29e9b4ba08aa99074fcba410755e5d967f66e7eaf998b99b8d5dcb0f65f363c14f8a6294fccecab8ed3f591b0c0de136023c3caea167997c0' +
    '1d69e23efc7f3967ebae907146e0b01df583d68774076ea3842fee38aa63c05b93b94a8a557a736ceab30368cc376e00db2134dfcf0529c99ff0a82fc4a04bbbbf3f0b8a3ec5fa655db78c29dca6a8ad' +
    '640d3d1962d3ec52cde816a9e5f4b3c6112194ed1764c090717db3594c1ed597246bcc1aa6cffbb4426fa15faca32625f4f73b99edf2e26ed5f70a4bfb4f75d30648c935d7fb2f789a57034282f021dc' +
    'a23ceb04c050d35377cdbb676c4b4d37e2c68f6b6da36a35a1cbffe134ba58179bd9dee0d4dff7b780d87e5d0743fa7334353de995886ca907d125531152f92d1e755e0d26b88c7a2180a47703efa4ed' +
    '32504397f49e3b06a2d7c158d17a7343f282e14959d34630ce3701a26f1809d82fcd239577ff8b9583e1b78ef8c0f9df3cdd9ebcd872d71d43e65f3431b70e508bcdb0dad218b1f8b477521e74c1668c' +
    '3237b8fa92c0aad0ce4facfb0d8b24ba69a303c8e75678c3227a926de0b0b31b6aa0f178e918f47993470dcf22d983c3719ab6c3521b4bdae1557024e4a872d290c9a4c1e2a0711f5c46d53fe71bbcf2' +
    'b64d8699a8a9a767b94f31b09ccfbf1f1f99f0009767ad8da0f1f860fd5b107db50725ede1f68c99d4f72d53c6f0d39c993e0cea724f7c6f8ec154378a3bf44a15620b70424b75662cd7343cd4926e79' +
    'a9261cc65385d9d261b1a6ac35af1b711529c92e60e303cb6ee3e1237dff994f76c6fae2b8fccf71f4c26b9669c02f6f96e02034afb64edbc10fcfec5f3302065f4a1ddfc5e1f4190c51d4e149ac260b' +
    '52c270a1d2f5c181f15fc81c7e33ed0dfff52fe627cadcf8ea867004d15f2c825233e7241748591f2e348d11f4244d02f26eb2789e2149dd4fdc981951433297ebbf8e4623ca5be327ab1d67c3ba870e' +
    '9d904a7ee786a03171537c33212c68918b42ea4f2fed5d9347797484746721f51a62a6556c45aac9e435f88739b0de3faed3be08bf67e7150892eb7e286dbc553a99d181b89260a30b65c7edf15edf5b' +
    '51fcf8a844b2a8fa39e6b047d224b96b32d382f50fd20297914fa40d6ca468b970c22113e0accd83f763e76b620d41ccbb0e15d4b4e21dd65350a11c40248743a077f17fdb72cb1c209f39471bbbcdf6' +
    '095ba56c93314ad47546e51a8f321c8944aa652fe21eed276b21f901df21270704930cc3741e92ec6310d150bd28398df9943c9b9f4b5b21ded383e0dd6ef6a15977accde77c216a2c4a5f9bf596de98' +
    'ebce843062d41e8aecf8a3973fe51a8c2329c506756a9c56a5f440e601144b4ebf6fd5dc9ba1030ddec859da89264dd5fa390086e018f4393aa54b777d5ddc484c89d4423b110e7ace04ce93e1b8aa4d' +
    'becf0202bfcaf52c4d3fcaa37a970c5bd7e5802083b8d1896520ffefd35aece91d8472453db8e0c09e5bc81c1ca5a7ae1f4d2957dde02a942c0c07f0b4a80ce0723fe6e0cd5a00e0838ba8beb318a286' +
    '1c8b3bac4ce879e3ca47ad4aa988f994e72ee75aab2795b852e9093864976e2bca1f12924319595978b00a9aa00c21419d052f0aa907b4d5599ad1462630d05a88146529971c11d6d24c8afe72364aaa' +
    '0849ac31d876b37820d9a57a8c2aaa017c17d7aa54ae7cf229a104b59aab1595f17f91ebb4b93c72cdad12db2bdab893e7cc31e4384242695e1a51eb4b0bf0b4884ed414149ed229ecc76f892cd41519' +
    '0f6743fd65540ed7814ccb574c1579be141b96e9f5aff91b2ac251559bbb0eed1b617f34f3bde6aca54ad57e0f15b86528e8e844d726703e69de03c80502eb1fc8bc97136fc90387f2e20ff7b007908b' +
    'e88d8978d03962a64ef6fbe39066b7e197ca21cc0597bca57056e546bb560cc212683cfe201f88b9beed1a2b84491aca102d4b5dcecb55c784d1e4a9627441e648dce46cd470d612648b62577ea935ed' +
    '9a15984af694c6b9c276bb4be507f352fb9b9201718b0d9b975f4e3ae223923e900511b6365d9c6c01e64acedc4bc8ef4ab535eb5404c9e47cbe511fd4c4ceb0326471e52939bca4a7555cbefd1b3d9c' +
    'b35cfad52c11ec350b11f8c573282565fc862f7770e2290b7edda74a41f4143a5795ceaa574460a9243bc640bb19071f33f033d67fa6f1a923a39d3dc22647871fd73bf2669ce7af376563add8fa0347' +
    '6dbf38a25bd31e59455b898e32d8a3bc660f6a654d3ba69f0ef66d6c0d54824debc87339b1ad1e0b64d7980da8dd3a8a5ac2277129cffc36a2aee7b46449856f17831ecc14e8444a87cde881e1f8cc0e' +
    '5768c0283b12fa975e7d48c2e8e9e1bd495090b132dafc97e2f628e52585eed21edd85d1444f42ec61cd2fbb7e4e5759bda1a163be0fd3dde613942f53791d1ab5cfe60042cdb8997c0a800e3517bb14' +
    '57f50d6c4664d667d401b6c165d6e38f68cb83053d308c9b620090f9013b827752c25edd1ff46abb9b217d2aba502e642547c61a4dc0e8bac1c8e2d84f2206ddf30e145ca3f8cd48024d9979cf97087f' +
    'fed622b9d292da744cd544e426030fdbae8d8fa06095950c9e9cf57ed5fa56a90550ea5e5f69eacb49cddabd40879ab664ce4bae4355778a8b247ff3f11aae200af202833af7993729ae9ffe432a2ab4' +
    '8b29f5717540759b1f0e67dcae332d1eb822e05452b6c3202445127914a24a6bd760f24408229a94204ae3df4d943ff523adf836b465c8bf3cee36a03dd4ce9015f32ddf639deb57d3a80899002071a0' +
    '878fc58f1b9e106b6c38941199a81a606a28ee5c43c63f9ae4ea95923bb5a3e7397e08b5fbac1a1283de3dfc87fd43b9d01b8da037fb3a0d5470dbb357bd5537123a97de8bb66bf8bd69d5b22132c389' +
    '061f99f2b625952055f10df76ad6f0598e40ab32752e94cbf132f92a57b8cfe239b44f9eefbb8449fb6c67fc2df7f0491ce4e8da7c150f5f7d8477ed68989d7d52dea0de9ce64364d6dde80688fbab7c' +
    '0a8b18719d1a647319d257d3fe502c185bdc6cae9ff2d243b001789124ba31d642568e1f620c754080e42ab9755c5ef5e87b740f4e70e78510f7d37731a6d03be5cd5029866bf2ef20c073fc844b8aa5' +
    'd2d679764f2b4256b3a2bc90d7568f8265de5fe9ac35a1555e62c654565734bf6f4636cede5e1d36a8750e530d7c14221bd3b78183978c077212162e0e3b51b97a5613948ec053f9c27f1a3e37389ee4' +
    '22e12d230b89f6030be77e045f40de2b181d881ca5a4a728f0ffe213162d2ac9b9c2a88c9b4deb41c4b8513ec9dbe9f26785b378e67bd52b338b43162525616fd29cbc8ce4b98b5b3a1026f4f17a07d8' +
    '2b83b4baf7567559e041ad665cd85ae5482647e9b66f679bc8343228a847b28998faf9e62fbc32c8d26ca29461860c952b4bc298e3b8282f07ac9a90f6aea20e51344ade440876238b570baed9b97278' +
    '4a3f6c535ff93b3ba3187ce0274e98d44f3a99a4e37fdfbb242dfed895915c8751a98374a5aac8e045586aaf4e31d3e8e5f874f1d92633827cc2a395195754d67b593ef4d35c39f87d594156fda1b4e7' +
    '247592343829acbab16595f80c6e18f9de8a47412ea199201e614abff905ec2bfc53ce17cdd221bb8e84a36ef3606f197fb568ffcb21b460ad60f7ab22dcf01fd7aab5d67ccf0d8292fb7c7f7ffa8d2f' +
    '255d6f2a229ccea5d3744f969b8c19eb87111c6e2cf5b38058109493d6b229f3f6109d69c39a2474dda2325a8c61a80597e5dda15dfb58d0c68ab0f79b5a6e76a23a3550efbcfc8435ebe8fcaed9ced6' +
    'eb2ccecb5390eb8a6a7f9327f72d7ace1431e4a645d829395a12b601ba1b522549f90af29cd8a887e43f158cefb9748a599d26c1d9f5fcec1da71f559d873b79d78bb5b95a71a35272b40c4f975e962c' +
    '5c160a5fb85d086b37ff358dfad353104d9b84b97c4eecd487cef328e20e85ec8aab6d366a437f376b61d25ce1e8cf1009717ee4b6033981c35c31f6a7871c251b77870c00bde825002ddc3f2d9e8c7a' +
    '352678c240fe9e9c368b37f4963dd374dccd6cd03cd0e4d8f1f5f5fadb2f9757a103b69e5c8e9db1a20e534394960114a780e11de4c511159286345eb15cb74b4805c63228b82e58885b2cc76b0b67a1' +
    '4fc96b827d192e068a76965cfc748f1f8af621e8015322555c86eb98b828a02759fcc13f10b97986261416d292f17e8f387d061f6b8c4528037087204955334901022a359373f79b4e35655f92500dd1' +
    '8a3a37d637d3dab928984c9dd7cbdf99afd33de78f47856149255d0a10f79cdc3197f99edb22881de339ae58b3bbdde42a49e06eb292b5ea6a7692f7682a29ebf14684561c421ee4bea35a783b53df7d' +
    '180ca692fc5bafacc827fbe21251b8d8075e930a02e2aa538f62f05b1aaeb3f01591bd9a044ba6ff4943991e9a12138b2b0c91314c971f132d442f2011fd37cb692fda15c91bf42d188d3ee7985e2f7f' +
    '163faca6a0112a61d8a8e371b0b5c0e6c6ccb75ab9ae1ed4d66746f76f4255be1147d75c30c3ec87d554a6b12e99a797b548146b1c5d60d4721585609e51381cc5250a05741f47278803f066ddf5e473' +
    '547e0a50116b07b0bc2cbb7baf80afad2e4e4f915cf7ecda708ab58efbd1677bf2a7bf17699b60676a65d873e07d4f95c3835cfbc3b2172e5965a8051eba41c1ccce9b4d654ad2766cfc9c65efe3c7ca' +
    '2b24b84bc7b23b0efc3652d41ee33293c074d636c88098a3e134b8c95afec3c5b4f1f8c8d09fd2e9047766935bcf1822c830860780e02c46b6f4aed4c2708d5b799378ffa0b687fd674137c1e1c0c443' +
    '2281c0ea0eb2e1ad14a3ffef136d07498da02f41465aa16094208323ef275d584b24a6a0106f503f7880de9a6c583f58541884ca34a142b991e07c257028e8f85bb822b31ee28468caa56a7a50f35246' +
    '244fdc0382eb0049cba580c66dc534ed2401e2c686506933b3c2882fd2110d7a5b4fb17b27bb82bb4d0fe3fddfab0f055d69004858f11ed97f4ea2443b10808ddbe11dc1be91d29f05550102fd09e12c' +
    'fcf4df26a4b8e3a4fda1a537b4fda9dd1ebfafaf44e109f6dc6ac812fb08fcf042e9b71dc93b6a9d79ac1929004d5db7d4a2756ea41955af31a5c0e3dc128979d89d1d8c368e099e8a629fe3ea46b41a' +
    'c6c9ffd3aa98aacfb70e96849c20a43da7bf11ba11b948e7bd456ac37d4efcfda8974beef58dd94b45e463d2f124524de1168d2977db58fa44fbf266d5f14ad05e4288154f01f2ab332fd591498049a4' +
    'f22b42857b5fe3de4598125c571f7029eef53ec6aad1fc58970daf0998aa3c8ef848312d334406bcef20f026afc4223b3929204fc3fcd8a947a76135f9684a9e81ac89598568810b08b1f5851f74b07f' +
    '07f59cef4e47200bf567a27cc31c3f428c577233b3d5e20d01aad233e942651032d8ce7e77efcf073953a12194644567edce3097af1132366ffc4a3dc6a459a88563daf62630e65e6d631afce39ef015' +
    '983b9fbc5a1e92274916bd85be9528c96a7c94f56796be519a550bb3f0e417f25d23e62bdab757965531815ff530e37d8d68f672feae5c1cd026c15d37fd0340e4a8cd536b9224bfb2c9bd40512dd1a4' +
    '864c7a221e8f4cfdbe92dded1f5054b53d38d1f3825c106abfa8d8d5609abe026f34049bbbe33c8420f8204d68b41e41539a54901a5925b3feea87eb645658eaa11f2d02b077449111b795bcc0840819' +
    '56cdbcf804a5edd510efdd859c95869e1081ac6708bf55bbea255bb223721f4dbb8bd6f4af7f1de53b6e9e812918d4b901f5036ac26be18f65bce48706476eb707366674f8b04c98bb7faf58ca303b28' +
    '237427fe5f49b02ab9fc7caf547de9e8f97c3b733eca2889a89e566bfe02ede7e9a99e7184cc9dd95ff58c8dcb3fc4497ce37085548cd9e2d971cdf72412980fc9ffe2654344958365dd9c9a19f65c5b' +
    '4278fc7fa7538d80f18acc6f700fe6db8ded5eccb6ab2b536044857b700699edfd8994cf49c553ed2710f908bef08a3778be24048e295128f89889e48102d208c22960fca3dd5b377ae5a6ba0d80c66c' +
    '7124393b49b71be73c9ecfc75aaf325ee941cc15fb553cc57f91a00be52dc01d02aca72558e0dab5589d32a71b4c5eae93f651d3b179af0c5b2804d4438ce476a2b186cbaf26bfc35f16b86e95b1eddd' +
    'fb6596e94fe22959f8e04932b918e9f5493163ba780fda8b3b28abe3ca38d708e814e0da55dee84e82d863b50b1ee6cbc7ab20997bed0cc12533b09450b9f2d9aec7b34bff3a369d039f60ef55efab92' +
    '13d245f1073bb0391cfa9fac4ac93052428e68926a270af46ef890ab8eddf21a3b59c36a0358f0746176e4e1bca717e442d10a88ad490f957933f88c444ceb208ce2e646da5947eb665328edd6ef76f7' +
    '0eada8317c3eb2fbbed4ef045fdf9e9124f293bee1dca945fe27cf1d95d4d2e7729fc9d1df548d8f71684d3abe7d6ed9edcdf76d0b6f4117e70217585bde3d512887019d9ea555c342a48febdcee3b12' +
    '09e52edcd535e483396810142475ed0d6b7242833a54afc1bf873aee602e01dd82c1ae22f41cfb55ae3ad50b262ab61d411236a9042bfb4cfbb47797774b4cdff25861a9bf6c4573dc69089c89de8f37' +
    'c19746515a071a4acf162d5a1ceac0652fc713f16a25c154417112d207f058cf4c2e74537297408c0ec9eb7ce59e3f1953835020990349ecf4ee6bbc1bc0bf0bfc1f376a98eae8271bfdd9d4d680d4c5' +
    'a18aef2c5a9c2a1f46c2979e146baccca84a5e8b537a24c019aaca59cb120cb7cba683d6d6f8b86c72eaec95c7a9bffdd87b81f830eab3692fd43449b3a7a5afb59dd6e21b26bbad0b34291590502db7' +
    '717430ab880593fe0a2b49ce272b1df6e8a0d8332793751e900054bb62b3df6d4a6a5f8c780b603c23466a9972b8885a76112da7f65f3d7d2fca8bc3861eec90042f470046dbd70552e5032c748a47d5' +
    '71706432215465a2f088e630eec327ca1eb4381bf3512fb712b0204c9a4ac913269908e94ca2ad2ba6ed5a5e811f99889a8fea6b367145aa878f9edad421994f694fd0f15448cf64a42ed8267fd6d33e' +
    '68688c007228388829d5f12ef7784b4083ac085b42f208874dee681cdfad966cbf11e8f86bf251e4d63b3c3c3b51fccfcf1ebdf6f45e735e8b9ffe25e2893cfbcf434b76ee991de18c19a33d882338c2' +
    'eb15db004b58784d95007c4f1d5c6361f51094fe383db6cba08c27971ac878540b4323554af63096bd15a67bad828e555f5e3c919c4eb2b48a1fa465d59ec4eec39d2f3ae84672b877b96e51e7bdcaee' +
    'f4210c789c7332dc7ebc5b5aa0a07b47ee44daf7b22bc55ccf35e799b35063047a1169cb500294db8508d4b7841e654222436069baa3d23d5d2b2e46114cba6ec021f3df4d0954d145fecdd6d19a96c6' +
    '8814d0e05924345d574cc5afed36aea1dbfb88c78f658f8c3c74c1d95e30afe37b09ed99782b3ed606668be2b8c6997e39e90cbb22f1b1ab22022689328b95d31ce62edea41499a2d53f1ac02a9f700d' +
    'a5181a60cfabea7cc9efab9b809ec5991f23238cb355dc14cb0d189e63d2535958a80704dc3a188af5dd51edd15939b84b4af272f189b58107c33b259a15349ea88d407b28e7a2ec65238cc8b2de7e65' +
    'f3f9d55dcd427d754acafedb672535731a5d6ea533ab7713996ac920408687a4f73ce2c66cd51bea9edda46bcd58132834ac39ca809410849fc179ec18d413db03bebc3ff4e2336e4ae5c51c7668be22' +
    '1553efd2098b6485d4f006707de78c0a39402f060b5b959fb8e5d696aab750c7d0e4899e7427f99e89f474390d37f2d411ce6e05a017e1ca46e1221f2f114e21736cdb10f5263b33d10f84bee7c3dade' +
    '98359f60c4217ba7facd7c1b70da82dfba4d31caa9b1d547cd47c48788b4d8f85266c3dda7efd4315dea0a987fe9c46f08ed50e06ff149ec0da1b9419f64a3ce365cd9111be9c90b9e1f1a071b7ab14f' +
    '389fa094828d5e63987217aa7f58fb6ce0bf10e95e162ddae6ccf0592e04f10e8b60415615715bcfc44551932a5df17aab8ae95e3e6676702e075c9d3ef6b577f15fd6354fa0020ab30fa82f0d7f656d' +
    '7b2c3634ea471802c4f92721170a8aa50fe322bfc554f15113365cadc16325e511622ce912df805bc926ab3bfbddbab36fe79f3fa49766a816fc943ce18217fb67cac15a16c6bb3062aaf2441f042a8c' +
    'd23d360f4bd2d1ac03e29b74d2def4ce6434c6b14093debcf8d1e54876ba995ba1a6e32c4e66ac278f3e6f3b3b0e3f1b14198046b2b78eb18a11ee75aa5fd9274e9e09a1a96ae3b499ca47483f10433c' +
    '37064fd42fca41db21232b6a0c276e6045b760ef53cdc03fd13874c4caabf3a81cfa2ce199260cb5804a7f7d95b051ba71b787a505ce0b92450b55c7cf80e0b83a06b61e81fb083bfa4f22f69892d046' +
    '3a3a85e4824ba27f4e10e046efa49dae839b7360890630db91270d04a0468964d6b9f4378c3be143f1d75754c7332de8a5d480024c4a2caa04626630dd297d91b31e0b853eba1388e9a41f2d32469b84' +
    'a6b3538fdc89d87472a5fddb71a6afba1fbb259a14bfa747adfe8bcdc6281ae97bd62c87d4fee0f9faaa073db7052ea6370f00614ea1498e2949599516293681f030db0ca7d5617e73c59d9cdc56f111' +
    '020af4154e3cfe6a8be4cf96ff102bf85d7d5249b1a7aeea4647eba55a672036a47ac7cc51abf873c9a8c5ad0902578ce7012827e1aee227e1d54f50e6a356c0536756300340e9992b16e4c45b6b660c' +
    '7577aa13a99d445483eb9af32d1b36b01a50deeb';
var
  Data: TBytes;
  R: TRandomnessTestResult;
begin
  Data := HexToBytes(DataEHex);
  Assert.AreEqual(Integer(12500), Integer(Length(Data)));
  R := TRandomnessTests.BinaryMatrixRank(Data, 100000);
  Assert.AreEqual(0.532069, R.PValue, 1E-5, R.Detail);
  Assert.IsTrue(R.Passed);
end;

{ Degenerate-sequence sanity checks - unambiguous regardless of exact NIST numbers }

procedure TValidateRNGTests.TestFrequency_AllZeros_FailsDecisively;
var
  Bits: TBytes;
  R: TRandomnessTestResult;
begin
  SetLength(Bits, 25);
  FillChar(Bits[0], 25, 0);
  R := TRandomnessTests.Frequency(Bits, 200);
  Assert.IsTrue(R.PValue < 1E-6);
  Assert.IsFalse(R.Passed);
end;

procedure TValidateRNGTests.TestFrequency_AllOnes_FailsDecisively;
var
  Bits: TBytes;
  R: TRandomnessTestResult;
begin
  SetLength(Bits, 25);
  FillChar(Bits[0], 25, $FF);
  R := TRandomnessTests.Frequency(Bits, 200);
  Assert.IsTrue(R.PValue < 1E-6);
  Assert.IsFalse(R.Passed);
end;

procedure TValidateRNGTests.TestRuns_Alternating_FailsDecisively;
var
  Bits: TBytes;
  R: TRandomnessTestResult;
begin
  SetLength(Bits, 25);
  FillChar(Bits[0], 25, $AA); // 10101010...
  R := TRandomnessTests.Runs(Bits, 200);
  Assert.IsTrue(R.PValue < 1E-6);
  Assert.IsFalse(R.Passed);
end;

procedure TValidateRNGTests.TestFrequency_Alternating_Passes;
var
  Bits: TBytes;
  R: TRandomnessTestResult;
begin
  SetLength(Bits, 25);
  FillChar(Bits[0], 25, $AA);
  R := TRandomnessTests.Frequency(Bits, 200);
  Assert.IsTrue(R.Passed); // exactly balanced ones/zeros
end;

{ Minimum-length / parameter validation }

procedure TValidateRNGTests.TestFrequency_TooShort_Raises;
var
  Bits: TBytes;
begin
  SetLength(Bits, 4);
  Assert.WillRaise(
    procedure begin TRandomnessTests.Frequency(Bits, 32); end,
    ERandomnessTestError);
end;

procedure TValidateRNGTests.TestBinaryMatrixRank_TooShort_Raises;
var
  Bits: TBytes;
begin
  SetLength(Bits, 100);
  Assert.WillRaise(
    procedure begin TRandomnessTests.BinaryMatrixRank(Bits, 800); end,
    ERandomnessTestError);
end;

procedure TValidateRNGTests.TestLongestRunOfOnes_OutOfSupportedRange_Raises;
var
  Bits: TBytes;
begin
  SetLength(Bits, 10);
  Assert.WillRaise(
    procedure begin TRandomnessTests.LongestRunOfOnes(Bits, 64); end,
    ERandomnessTestError);
end;

procedure TValidateRNGTests.TestApproximateEntropy_MZero_Raises;
var
  Bits: TBytes;
begin
  SetLength(Bits, 13);
  Assert.WillRaise(
    procedure begin TRandomnessTests.ApproximateEntropy(Bits, 100, 0); end,
    ERandomnessTestError);
end;

{ Live CSRNG integration }

procedure TValidateRNGTests.TestRunSuite_LiveCSRNG_AllResultsSane;
var
  Provider: ICSPRNGProvider;
  Data: TBytes;
  Results: TArray<TRandomnessTestResult>;
  R: TRandomnessTestResult;
begin
  Provider := GetCSPRNGProvider;
  Data := Provider.GetBytes(5000); // 40,000 bits: satisfies BinaryMatrixRank's
                                    // minimum (38,912) but not
                                    // LongestRunOfOnes' supported range
                                    // (<6272) - exercises the skip path too.
  Results := TRandomnessTests.RunSuite(Data, 40000);
  Assert.AreEqual(Integer(7), Integer(Length(Results)));
  for R in Results do
  begin
    if R.PValue = -1 then
      Assert.IsTrue(R.Detail.StartsWith('skipped'), 'A skipped result must explain why')
    else
    begin
      Assert.IsTrue(R.PValue >= 0, R.TestName + ' P-value below 0');
      Assert.IsTrue(R.PValue <= 1, R.TestName + ' P-value above 1');
    end;
  end;
end;

procedure TValidateRNGTests.TestRunSuite_ProviderOverload_Works;
var
  Provider: ICSPRNGProvider;
  Results: TArray<TRandomnessTestResult>;
begin
  Provider := GetCSPRNGProvider;
  Results := TRandomnessTests.RunSuite(Provider, 40000);
  Assert.AreEqual(Integer(7), Integer(Length(Results)));
end;

end.
